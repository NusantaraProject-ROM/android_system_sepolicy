version := $(version_under_treble_tests)

include $(CLEAR_VARS)
# For Treble builds run tests verifying that processes are properly labeled and
# permissions granted do not violate the treble model.  Also ensure that treble
# compatibility guarantees are upheld between SELinux version bumps.
LOCAL_MODULE := treble_sepolicy_tests_$(version)
LOCAL_LICENSE_KINDS := SPDX-license-identifier-Apache-2.0 legacy_unencumbered
LOCAL_LICENSE_CONDITIONS := notice unencumbered
LOCAL_NOTICE_FILE := $(LOCAL_PATH)/NOTICE
LOCAL_MODULE_CLASS := FAKE
LOCAL_MODULE_TAGS := optional
SYSTEM_EXT_PREBUILT_POLICY  := $(BOARD_SYSTEM_EXT_PREBUILT_DIR)
PRODUCT_PREBUILT_POLICY  := $(BOARD_PRODUCT_PREBUILT_DIR)

include $(BUILD_SYSTEM)/base_rules.mk

# $(version)_plat - the platform policy shipped as part of the $(version) release.  This is
# built to enable us to determine the diff between the current policy and the
# $(version) policy, which will be used in tests to make sure that compatibility has
# been maintained by our mapping files.
$(version)_PLAT_PUBLIC_POLICY := $(LOCAL_PATH)/prebuilts/api/$(version)/public
$(version)_PLAT_PRIVATE_POLICY := $(LOCAL_PATH)/prebuilts/api/$(version)/private
policy_files := $(call build_policy, $(sepolicy_build_files), $($(version)_PLAT_PUBLIC_POLICY) $($(version)_PLAT_PRIVATE_POLICY))
$(version)_plat_policy.conf := $(intermediates)/$(version)_plat_policy.conf
$($(version)_plat_policy.conf): PRIVATE_MLS_SENS := $(MLS_SENS)
$($(version)_plat_policy.conf): PRIVATE_MLS_CATS := $(MLS_CATS)
$($(version)_plat_policy.conf): PRIVATE_TARGET_BUILD_VARIANT := user
$($(version)_plat_policy.conf): PRIVATE_TGT_ARCH := $(my_target_arch)
$($(version)_plat_policy.conf): PRIVATE_TGT_WITH_ASAN := $(with_asan)
$($(version)_plat_policy.conf): PRIVATE_TGT_WITH_NATIVE_COVERAGE := $(with_native_coverage)
$($(version)_plat_policy.conf): PRIVATE_ADDITIONAL_M4DEFS := $(LOCAL_ADDITIONAL_M4DEFS)
$($(version)_plat_policy.conf): PRIVATE_SEPOLICY_SPLIT := true
$($(version)_plat_policy.conf): PRIVATE_POLICY_FILES := $(policy_files)
$($(version)_plat_policy.conf): $(policy_files) $(M4)
	$(transform-policy-to-conf)
	$(hide) sed '/dontaudit/d' $@ > $@.dontaudit

policy_files :=

built_$(version)_plat_sepolicy := $(intermediates)/built_$(version)_plat_sepolicy
$(built_$(version)_plat_sepolicy): PRIVATE_ADDITIONAL_CIL_FILES := \
  $(call build_policy, technical_debt.cil , $($(version)_PLAT_PRIVATE_POLICY))
$(built_$(version)_plat_sepolicy): PRIVATE_NEVERALLOW_ARG := $(NEVERALLOW_ARG)
$(built_$(version)_plat_sepolicy): $($(version)_plat_policy.conf) $(HOST_OUT_EXECUTABLES)/checkpolicy \
  $(HOST_OUT_EXECUTABLES)/secilc \
  $(call build_policy, technical_debt.cil, $($(version)_PLAT_PRIVATE_POLICY)) \
  $(built_sepolicy_neverallows)
	@mkdir -p $(dir $@)
	$(hide) $(CHECKPOLICY_ASAN_OPTIONS) $(HOST_OUT_EXECUTABLES)/checkpolicy -M -C -c \
		$(POLICYVERS) -o $@ $<
	$(hide) cat $(PRIVATE_ADDITIONAL_CIL_FILES) >> $@
	$(hide) $(HOST_OUT_EXECUTABLES)/secilc -m -M true -G -c $(POLICYVERS) $(PRIVATE_NEVERALLOW_ARG) $@ -o $@ -f /dev/null

$(version)_plat_policy.conf :=

# $(version)_compat - the current plat_sepolicy.cil built with the compatibility file
# targeting the $(version) SELinux release.  This ensures that our policy will build
# when used on a device that has non-platform policy targetting the $(version) release.
$(version)_compat := $(intermediates)/$(version)_compat
$(version)_mapping.cil := $(call intermediates-dir-for,ETC,plat_$(version).cil)/plat_$(version).cil
$(version)_mapping.ignore.cil := \
    $(call intermediates-dir-for,ETC,$(version).ignore.cil)/$(version).ignore.cil
$(version)_prebuilts_dir := $(LOCAL_PATH)/prebuilts/api/$(version)

# vendor_sepolicy.cil and plat_pub_versioned.cil are the new design to replace
# nonplat_sepolicy.cil.
$(version)_nonplat := $($(version)_prebuilts_dir)/vendor_sepolicy.cil \
$($(version)_prebuilts_dir)/plat_pub_versioned.cil
ifeq (,$(wildcard $($(version)_nonplat)))
$(version)_nonplat := $($(version)_prebuilts_dir)/nonplat_sepolicy.cil
endif

$($(version)_compat): PRIVATE_CIL_FILES := \
$(built_plat_cil) $($(version)_mapping.cil) $($(version)_nonplat)
$($(version)_compat): $(HOST_OUT_EXECUTABLES)/secilc \
$(built_plat_cil) $($(version)_mapping.cil) $($(version)_nonplat)
	$(hide) $(HOST_OUT_EXECUTABLES)/secilc -m -M true -G -N -c $(POLICYVERS) \
		$(PRIVATE_CIL_FILES) -o $@ -f /dev/null


# $(version)_mapping.combined.cil - a combination of the mapping file used when
# combining the current platform policy with nonplatform policy based on the
# $(version) policy release and also a special ignored file that exists purely for
# these tests.
$(version)_mapping.combined.cil := $(intermediates)/$(version)_mapping.combined.cil
$($(version)_mapping.combined.cil): $($(version)_mapping.cil) $($(version)_mapping.ignore.cil)
	mkdir -p $(dir $@)
	cat $^ > $@

$(LOCAL_BUILT_MODULE): ALL_FC_ARGS := $(all_fc_args)
$(LOCAL_BUILT_MODULE): PRIVATE_SEPOLICY := $(built_sepolicy)
$(LOCAL_BUILT_MODULE): PRIVATE_SEPOLICY_OLD := $(built_$(version)_plat_sepolicy)
$(LOCAL_BUILT_MODULE): PRIVATE_COMBINED_MAPPING := $($(version)_mapping.combined.cil)
$(LOCAL_BUILT_MODULE): PRIVATE_PLAT_SEPOLICY := $(built_plat_sepolicy)
$(LOCAL_BUILT_MODULE): PRIVATE_PLAT_PUB_SEPOLICY := $(base_plat_pub_policy.cil)
$(LOCAL_BUILT_MODULE): PRIVATE_FAKE_TREBLE :=
ifeq ($(PRODUCT_FULL_TREBLE_OVERRIDE),true)
# TODO(b/113124961): remove fake-treble
$(LOCAL_BUILT_MODULE): PRIVATE_FAKE_TREBLE := --fake-treble
endif # PRODUCT_FULL_TREBLE_OVERRIDE = true
$(LOCAL_BUILT_MODULE): $(HOST_OUT_EXECUTABLES)/treble_sepolicy_tests \
  $(all_fc_files) $(built_sepolicy) $(built_plat_sepolicy) \
  $(base_plat_pub_policy.cil) \
  $(built_$(version)_plat_sepolicy) $($(version)_compat) $($(version)_mapping.combined.cil)
	@mkdir -p $(dir $@)
	$(hide) $(HOST_OUT_EXECUTABLES)/treble_sepolicy_tests -l \
		$(HOST_OUT)/lib64/libsepolwrap.$(SHAREDLIB_EXT) $(ALL_FC_ARGS) \
		-b $(PRIVATE_PLAT_SEPOLICY) -m $(PRIVATE_COMBINED_MAPPING) \
		-o $(PRIVATE_SEPOLICY_OLD) -p $(PRIVATE_SEPOLICY) \
		-u $(PRIVATE_PLAT_PUB_SEPOLICY) \
		$(PRIVATE_FAKE_TREBLE)
	$(hide) touch $@


$(version)_mapping.combined.cil :=

# $(version)_system_ext - the system_ext policy shipped as part of the $(version) release.  This is
# built to enable us to determine the diff between the current policy and the
# $(version) policy, which will be used in tests to make sure that compatibility has
# been maintained by our mapping files.

# adding the tests for version - 30 becuase system_ext policy introduced in android-R only.

ifneq ($(filter 30.0,$(version)),)
$(version)_SYSTEM_EXT_PUBLIC_POLICY := $(SYSTEM_EXT_PREBUILT_POLICY)/prebuilts/api/$(version)/public
$(version)_SYSTEM_EXT_PRIVATE_POLICY := $(SYSTEM_EXT_PREBUILT_POLICY)/prebuilts/api/$(version)/private
ifneq (,$(SYSTEM_EXT_PREBUILT_POLICY))
system_ext_policy_files := $(call build_policy, $(sepolicy_build_files), $($(version)_PLAT_PUBLIC_POLICY) $($(version)_PLAT_PRIVATE_POLICY) \
                $($(version)_SYSTEM_EXT_PUBLIC_POLICY) $($(version)_SYSTEM_EXT_PRIVATE_POLICY))
$(version)_system_ext_policy.conf := $(intermediates)/$(version)_system_ext_policy.conf
$($(version)_system_ext_policy.conf): PRIVATE_MLS_SENS := $(MLS_SENS)
$($(version)_system_ext_policy.conf): PRIVATE_MLS_CATS := $(MLS_CATS)
$($(version)_system_ext_policy.conf): PRIVATE_TARGET_BUILD_VARIANT := user
$($(version)_system_ext_policy.conf): PRIVATE_TGT_ARCH := $(my_target_arch)
$($(version)_system_ext_policy.conf): PRIVATE_TGT_WITH_ASAN := $(with_asan)
$($(version)_system_ext_policy.conf): PRIVATE_TGT_WITH_NATIVE_COVERAGE := $(with_native_coverage)
$($(version)_system_ext_policy.conf): PRIVATE_ADDITIONAL_M4DEFS := $(LOCAL_ADDITIONAL_M4DEFS)
$($(version)_system_ext_policy.conf): PRIVATE_SEPOLICY_SPLIT := true
$($(version)_system_ext_policy.conf): PRIVATE_POLICY_FILES := $(system_ext_policy_files)
$($(version)_system_ext_policy.conf): $(system_ext_policy_files) $(M4)
	$(transform-policy-to-conf)
	$(hide) sed '/dontaudit/d' $@ > $@.dontaudit

system_ext_policy_files :=

built_$(version)_system_ext_sepolicy := $(intermediates)/built_$(version)_system_ext_sepolicy
$(built_$(version)_system_ext_sepolicy): PRIVATE_ADDITIONAL_CIL_FILES := \
  $(call build_policy, technical_debt.cil , $($(version)_SYSTEM_EXT_PRIVATE_POLICY))
$(built_$(version)_system_ext_sepolicy): PRIVATE_NEVERALLOW_ARG := $(NEVERALLOW_ARG)
$(built_$(version)_system_ext_sepolicy): $($(version)_system_ext_policy.conf) $(HOST_OUT_EXECUTABLES)/checkpolicy \
  $(HOST_OUT_EXECUTABLES)/secilc \
  $(call build_policy, technical_debt.cil, $($(version)_SYSTEM_EXT_PRIVATE_POLICY)) \
  $(built_sepolicy_neverallows)
	@mkdir -p $(dir $@)
	$(hide) $(CHECKPOLICY_ASAN_OPTIONS) $(HOST_OUT_EXECUTABLES)/checkpolicy -M -C -c \
                $(POLICYVERS) -o $@ $<
	$(hide) cat $(PRIVATE_ADDITIONAL_CIL_FILES) >> $@
	$(hide) $(HOST_OUT_EXECUTABLES)/secilc -m -M true -G -c $(POLICYVERS) $(PRIVATE_NEVERALLOW_ARG) $@ -o $@ -f /dev/null

$(version)_system_ext_policy.conf :=

# $(version)_compat - the current system_ext_sepolicy.cil built with the compatibility file
# targeting the $(version) SELinux release.  This ensures that our policy will build
# when used on a device that has non-system_extform policy targetting the $(version) release.

$(version)_system_ext_compat := $(intermediates)/$(version)_system_ext_compat
$(version)_mapping.cil := $(call intermediates-dir-for,ETC,plat_$(version).cil)/plat_$(version).cil \
    $(call intermediates-dir-for,ETC,system_ext_$(version).cil)/system_ext_$(version).cil

$(version)_mapping.ignore.cil := \
       $(call intermediates-dir-for,ETC,$(version).ignore.cil)/$(version).ignore.cil \
       $(call intermediates-dir-for,ETC,system_ext_$(version).ignore.cil)/system_ext_$(version).ignore.cil

$(version)_prebuilts_dir := $(SYSTEM_EXT_PREBUILT_POLICY)/prebuilts/api/$(version)

# vendor_sepolicy.cil and system_ext_pub_versioned.cil are the new design to replace
# nonplat_ext_sepolicy.cil.
$(version)_nonplat := $($(version)_prebuilts_dir)/vendor_sepolicy.cil \
$(LOCAL_PATH)/prebuilts/api/$(version)/plat_pub_versioned.cil $($(version)_prebuilts_dir)/system_ext_pub_versioned.cil
ifeq (,$(wildcard $($(version)_nonplat)))
$(version)_nonplat := $($(version)_prebuilts_dir)/nonplat_sepolicy.cil
endif

$($(version)_system_ext_compat): PRIVATE_CIL_FILES := \
$(built_plat_cil) $(built_system_ext_cil) $($(version)_mapping.cil) $($(version)_nonplat)
$($(version)_system_ext_compat): $(HOST_OUT_EXECUTABLES)/secilc \
$(built_plat_cil) $(built_system_ext_cil) $($(version)_mapping.cil) $($(version)_nonplat)
	$(hide) $(HOST_OUT_EXECUTABLES)/secilc -m -M true -G -N -c $(POLICYVERS) \
                $(PRIVATE_CIL_FILES) -o $@ -f /dev/null

# $(version)_mapping.combined.cil - a combination of the mapping file used when
# combining the current system_extform policy with nonsystem_extform policy based on the
# $(version) policy release and also a special ignored file that exists purely for
# these tests.

$(version)_mapping.combined.cil := $(intermediates)/$(version)_mapping.combined.cil
$($(version)_mapping.combined.cil): $($(version)_mapping.cil) $($(version)_mapping.ignore.cil)
	mkdir -p $(dir $@)
	cat $^ > $@

$(LOCAL_BUILT_MODULE): ALL_FC_ARGS := $(all_fc_args)
$(LOCAL_BUILT_MODULE): PRIVATE_SEPOLICY := $(built_sepolicy)
$(LOCAL_BUILT_MODULE): PRIVATE_SEPOLICY_OLD := $(built_$(version)_system_ext_sepolicy)
$(LOCAL_BUILT_MODULE): PRIVATE_COMBINED_MAPPING := $($(version)_mapping.combined.cil)
$(LOCAL_BUILT_MODULE): PRIVATE_SYSTEM_EXT_SEPOLICY := $(built_system_ext_sepolicy)
$(LOCAL_BUILT_MODULE): PRIVATE_SYSTEM_EXT_PUB_SEPOLICY := $(base_system_ext_pub_policy.cil)
$(LOCAL_BUILT_MODULE): PRIVATE_FAKE_TREBLE :=
ifeq ($(PRODUCT_FULL_TREBLE_OVERRIDE),true)
# TODO(b/113124961): remove fake-treble
$(LOCAL_BUILT_MODULE): PRIVATE_FAKE_TREBLE := --fake-treble
endif # PRODUCT_FULL_TREBLE_OVERRIDE = true
$(LOCAL_BUILT_MODULE): $(HOST_OUT_EXECUTABLES)/treble_sepolicy_tests \
  $(all_fc_files) $(built_sepolicy) $(built_system_ext_sepolicy) \
  $(base_system_ext_pub_policy.cil) \
  $(built_$(version)_system_ext_sepolicy) $($(version)_system_ext_compat) $($(version)_mapping.combined.cil)
	@mkdir -p $(dir $@)
	$(hide) $(HOST_OUT_EXECUTABLES)/treble_sepolicy_tests -l \
                $(HOST_OUT)/lib64/libsepolwrap.$(SHAREDLIB_EXT) $(ALL_FC_ARGS) \
                -b $(PRIVATE_SYSTEM_EXT_SEPOLICY) -m $(PRIVATE_COMBINED_MAPPING) \
                -o $(PRIVATE_SEPOLICY_OLD) -p $(PRIVATE_SEPOLICY) \
                -u $(PRIVATE_SYSTEM_EXT_PUB_SEPOLICY) \
                $(PRIVATE_FAKE_TREBLE)
	$(hide) touch $@

endif #($(version)_SYSTEM_EXT_PUBLIC_POLICY)
endif #$(version)

# $(version)_product - the product policy shipped as part of the $(version) release.  This is
# built to enable us to determine the diff between the current policy and the
# $(version) policy, which will be used in tests to make sure that compatibility has
# been maintained by our mapping files.

# adding the tests for version - 30 becuase product policy introduced in android-R only.

ifneq ($(filter 30.0,$(version)),)
$(version)_PRODUCT_PUBLIC_POLICY := $(PRODUCT_PREBUILT_POLICY)/prebuilts/api/$(version)/public
$(version)_PRODUCT_PRIVATE_POLICY := $(PRODUCT_PREBUILT_POLICY)/prebuilts/api/$(version)/private
ifneq (,$(PRODUCT_PREBUILT_POLICY))
product_policy_files := $(call build_policy, $(sepolicy_build_files), $($(version)_PLAT_PUBLIC_POLICY) $($(version)_PLAT_PRIVATE_POLICY) \
				$($(version)_SYSTEM_EXT_PUBLIC_POLICY) $($(version)_SYSTEM_EXT_PRIVATE_POLICY) \
                                $($(version)_PRODUCT_PUBLIC_POLICY) $($(version)_PRODUCT_PRIVATE_POLICY))

$(version)_product_policy.conf := $(intermediates)/$(version)_product_policy.conf
$($(version)_product_policy.conf): PRIVATE_MLS_SENS := $(MLS_SENS)
$($(version)_product_policy.conf): PRIVATE_MLS_CATS := $(MLS_CATS)
$($(version)_product_policy.conf): PRIVATE_TARGET_BUILD_VARIANT := user
$($(version)_product_policy.conf): PRIVATE_TGT_ARCH := $(my_target_arch)
$($(version)_product_policy.conf): PRIVATE_TGT_WITH_ASAN := $(with_asan)
$($(version)_product_policy.conf): PRIVATE_TGT_WITH_NATIVE_COVERAGE := $(with_native_coverage)
$($(version)_product_policy.conf): PRIVATE_ADDITIONAL_M4DEFS := $(LOCAL_ADDITIONAL_M4DEFS)
$($(version)_product_policy.conf): PRIVATE_SEPOLICY_SPLIT := true
$($(version)_product_policy.conf): PRIVATE_POLICY_FILES := $(product_policy_files)
$($(version)_product_policy.conf): $(product_policy_files) $(M4)
	$(transform-policy-to-conf)
	$(hide) sed '/dontaudit/d' $@ > $@.dontaudit

product_policy_files :=

built_$(version)_product_sepolicy := $(intermediates)/built_$(version)_product_sepolicy
$(built_$(version)_product_sepolicy): PRIVATE_ADDITIONAL_CIL_FILES := \
  $(call build_policy, technical_debt.cil , $($(version)_PRODUCT_PRIVATE_POLICY))
$(built_$(version)_product_sepolicy): PRIVATE_NEVERALLOW_ARG := $(NEVERALLOW_ARG)
$(built_$(version)_product_sepolicy): $($(version)_product_policy.conf) $(HOST_OUT_EXECUTABLES)/checkpolicy \
  $(HOST_OUT_EXECUTABLES)/secilc \
  $(call build_policy, technical_debt.cil, $($(version)_PRODUCT_PRIVATE_POLICY)) \
  $(built_sepolicy_neverallows)
	@mkdir -p $(dir $@)
	$(hide) $(CHECKPOLICY_ASAN_OPTIONS) $(HOST_OUT_EXECUTABLES)/checkpolicy -M -C -c \
                $(POLICYVERS) -o $@ $<
	$(hide) cat $(PRIVATE_ADDITIONAL_CIL_FILES) >> $@
	$(hide) $(HOST_OUT_EXECUTABLES)/secilc -m -M true -G -c $(POLICYVERS) $(PRIVATE_NEVERALLOW_ARG) $@ -o $@ -f /dev/null

$(version)_product_policy.conf :=

# $(version)_product_compat - the current product_sepolicy.cil built with the compatibility file
# targeting the $(version) SELinux release.  This ensures that our policy will build
# when used on a device that has non-productform policy targetting the $(version) release.

$(version)_product_compat := $(intermediates)/$(version)_product_compat

$(version)_mapping.cil := $(call intermediates-dir-for,ETC,plat_$(version).cil)/plat_$(version).cil \
    $(call intermediates-dir-for,ETC,system_ext_$(version).cil)/system_ext_$(version).cil \
    $(call intermediates-dir-for,ETC,product_$(version).cil)/product_$(version).cil

$(version)_mapping.ignore.cil := \
       $(call intermediates-dir-for,ETC,$(version).ignore.cil)/$(version).ignore.cil \
       $(call intermediates-dir-for,ETC,system_ext_$(version).ignore.cil)/system_ext_$(version).ignore.cil \
       $(call intermediates-dir-for,ETC,product_$(version).ignore.cil)/product_$(version).ignore.cil

$(version)_prebuilts_dir := $(PRODUCT_PREBUILT_POLICY)/prebuilts/api/$(version)

# vendor_sepolicy.cil and product_pub_versioned.cil are the new design to replace
# nonplat_ext_sepolicy.cil.
$(version)_nonplat := $($(version)_prebuilts_dir)/vendor_sepolicy.cil \
      $(LOCAL_PATH)/prebuilts/api/$(version)/plat_pub_versioned.cil \
      $(SYSTEM_EXT_PREBUILT_POLICY)/prebuilts/api/$(version)/system_ext_pub_versioned.cil \
      $($(version)_prebuilts_dir)/product_pub_versioned.cil
ifeq (,$(wildcard $($(version)_nonplat)))
$(version)_nonplat := $($(version)_prebuilts_dir)/nonplat_sepolicy.cil
endif

$($(version)_product_compat): PRIVATE_CIL_FILES := \
$(built_plat_cil) $(built_system_ext_cil) $(built_product_cil) $($(version)_mapping.cil) $($(version)_nonplat)
$($(version)_product_compat): $(HOST_OUT_EXECUTABLES)/secilc \
$(built_plat_cil) $(built_system_ext_cil) $(built_product_cil) $($(version)_mapping.cil) $($(version)_nonplat)
	$(hide) $(HOST_OUT_EXECUTABLES)/secilc -m -M true -G -N -c $(POLICYVERS) \
                $(PRIVATE_CIL_FILES) -o $@ -f /dev/null

# $(version)_mapping.combined.cil - a combination of the mapping file used when
# combining the current productform policy with nonproductform policy based on the
# $(version) policy release and also a special ignored file that exists purely for
# these tests.

$(version)_mapping.combined.cil := $(intermediates)/$(version)_mapping.combined.cil
$($(version)_mapping.combined.cil): $($(version)_mapping.cil) $($(version)_mapping.ignore.cil)
	mkdir -p $(dir $@)
	cat $^ > $@

$(LOCAL_BUILT_MODULE): ALL_FC_ARGS := $(all_fc_args)
$(LOCAL_BUILT_MODULE): PRIVATE_SEPOLICY := $(built_sepolicy)
$(LOCAL_BUILT_MODULE): PRIVATE_SEPOLICY_OLD := $(built_$(version)_product_sepolicy)
$(LOCAL_BUILT_MODULE): PRIVATE_COMBINED_MAPPING := $($(version)_mapping.combined.cil)
$(LOCAL_BUILT_MODULE): PRIVATE_PRODUCT_SEPOLICY := $(built_product_sepolicy)
$(LOCAL_BUILT_MODULE): PRIVATE_PRODUCT_PUB_SEPOLICY := $(base_product_pub_policy.cil)
$(LOCAL_BUILT_MODULE): PRIVATE_FAKE_TREBLE :=
ifeq ($(PRODUCT_FULL_TREBLE_OVERRIDE),true)
# TODO(b/113124961): remove fake-treble
$(LOCAL_BUILT_MODULE): PRIVATE_FAKE_TREBLE := --fake-treble
endif # PRODUCT_FULL_TREBLE_OVERRIDE = true
$(LOCAL_BUILT_MODULE): $(HOST_OUT_EXECUTABLES)/treble_sepolicy_tests \
  $(all_fc_files) $(built_sepolicy) $(built_product_sepolicy) \
  $(base_product_pub_policy.cil) \
  $(built_$(version)_product_sepolicy) $($(version)_product_compat) $($(version)_mapping.combined.cil)
	@mkdir -p $(dir $@)
	$(hide) $(HOST_OUT_EXECUTABLES)/treble_sepolicy_tests -l \
                $(HOST_OUT)/lib64/libsepolwrap.$(SHAREDLIB_EXT) $(ALL_FC_ARGS) \
                -b $(PRIVATE_PRODUCT_SEPOLICY) -m $(PRIVATE_COMBINED_MAPPING) \
                -o $(PRIVATE_SEPOLICY_OLD) -p $(PRIVATE_SEPOLICY) \
                -u $(PRIVATE_PRODUCT_PUB_SEPOLICY) \
                $(PRIVATE_FAKE_TREBLE)
	$(hide) touch $@

endif #($(version)_PRODUCT_PUBLIC_POLICY)
endif #$(version)

$(version)_PLAT_PUBLIC_POLICY :=
$(version)_PLAT_PRIVATE_POLICY :=
$(version)_SYSTEM_EXT_PUBLIC_POLICY :=
$(version)_SYSTEM_EXT_PRIVATE_POLICY :=
$(version)_PRODUCT_PUBLIC_POLICY :=
$(version)_PRODUCT_PRIVATE_POLICY :=
$(version)_compat :=
$(version)_mapping.cil :=
$(version)_system_ext_compat :=
$(version)_product_compat :=
$(version)_mapping.combined.cil :=
$(version)_mapping.ignore.cil :=
$(version)_nonplat :=
$(version)_prebuilts_dir :=
built_$(version)_plat_sepolicy :=
version :=
version_under_treble_tests :=
