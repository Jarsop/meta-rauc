# Class for creating rauc bundles
#
# Description:
# 
# You have to set the slot images in your recipe file following this example:
#
#   RAUC_BUNDLE_COMPATIBLE ?= "My Super Product"
#   RAUC_BUNDLE_VERSION ?= "v2015-06-07-1"
#   
#   RAUC_BUNDLE_HOOKS[file] ?= "hook.sh"
#   RAUC_BUNDLE_HOOKS[hooks] ?= "install-check"
#
#   RAUC_BUNDLE_SLOTS ?= "rootfs kernel dtb bootloader"
#   
#   RAUC_SLOT_rootfs ?= "core-image-minimal"
#   RAUC_SLOT_rootfs[fstype] = "ext4"
#   RAUC_SLOT_rootfs[hooks] ?= "install;post-install"
#   
#   RAUC_SLOT_kernel ?= "linux-yocto"
#   RAUC_SLOT_kernel[type] ?= "kernel"
#   
#   RAUC_SLOT_bootloader ?= "barebox"
#   RAUC_SLOT_bootloader[type] ?= "boot"
#   RAUC_SLOT_bootloader[file] ?= "barebox.img"
#
#   RAUC_SLOT_dtb ?= linux-yocto
#   RAUC_SLOT_dtb[type] ?= "file"
#   RAUC_SLOT_dtb[file] ?= "${MACHINE}.dtb"
#
# To use a different image name, e.g. for variants
#   RAUC_SLOT_dtb ?= linux-yocto
#   RAUC_SLOT_dtb[name] ?= "dtb.my,compatible"
#   RAUC_SLOT_dtb[type] ?= "file"
#   RAUC_SLOT_dtb[file] ?= "${MACHINE}-variant1.dtb"
#
# Additionally you need to provide a certificate and a key file
#
#   RAUC_KEY_FILE ?= "development-1.key.pem"
#   RAUC_CERT_FILE ?= "development-1.cert.pem"

LICENSE = "MIT"

PACKAGE_ARCH = "${MACHINE_ARCH}"

PACKAGES = ""
INHIBIT_DEFAULT_DEPS = "1"

RAUC_IMAGE_FSTYPE ??= "${@(d.getVar('IMAGE_FSTYPES') or "").split()[0]}"
RAUC_IMAGE_FSTYPE[doc] = "Specifies the default file name extension to expect for collecting image artifacts. Defaults to first element set in IMAGE_FSTYPES."

do_fetch[cleandirs] = "${S}"
do_patch[noexec] = "1"
do_configure[noexec] = "1"
do_compile[noexec] = "1"
do_install[noexec] = "1"
do_populate_sysroot[noexec] = "1"
do_package[noexec] = "1"
do_package_qa[noexec] = "1"
do_packagedata[noexec] = "1"
do_package_write_ipk[noexec] = "1"
do_package_write_deb[noexec] = "1"
do_package_write_rpm[noexec] = "1"

RAUC_BUNDLE_COMPATIBLE  ??= "${MACHINE}-${TARGET_VENDOR}"
RAUC_BUNDLE_VERSION     ??= "${PV}"
RAUC_BUNDLE_DESCRIPTION ??= "${SUMMARY}"
RAUC_BUNDLE_BUILD       ??= "${DATETIME}"
RAUC_BUNDLE_BUILD[vardepsexclude] = "DATETIME"
RAUC_BUNDLE_COMPATIBLE[doc] = "Specifies the mandatory bundle compatible string. See RAUC documentation for more details."
RAUC_BUNDLE_VERSION[doc] = "Specifies the bundle version string. See RAUC documentation for more details."
RAUC_BUNDLE_DESCRIPTION[doc] = "Specifies the bundle description string. See RAUC documentation for more details."
RAUC_BUNDLE_BUILD[doc] = "Specifies the bundle build stamp. See RAUC documentation for more details."

RAUC_BUNDLE_SLOTS[doc] = "Space-separated list of slot classes to include in bundle (manifest)"
RAUC_BUNDLE_HOOKS[doc] = "Allows to specify an additional hook executable and bundle hooks (via varflags '[file'] and ['hooks'])"

# Create dependency list from images
python __anonymous() {
    d.appendVarFlag('do_unpack', 'vardeps', ' RAUC_BUNDLE_HOOKS')
    for slot in (d.getVar('RAUC_BUNDLE_SLOTS') or "").split():
        slotflags = d.getVarFlags('RAUC_SLOT_%s' % slot)
        imgtype = slotflags.get('type') if slotflags else None
        if not imgtype:
            bb.debug(1, "No [type] given for slot '%s', defaulting to 'image'" % slot)
            imgtype = 'image'
        image = d.getVar('RAUC_SLOT_%s' % slot)

        if not image:
            bb.error("No image set for slot '%s'. Specify via 'RAUC_SLOT_%s = \"<recipe-name>\"'" % (slot, slot))
            return

        d.appendVarFlag('do_unpack', 'vardeps', ' RAUC_SLOT_%s' % slot)
        depends = slotflags.get('depends') if slotflags else None
        if depends:
            d.appendVarFlag('do_unpack', 'depends', ' ' + depends)
            continue

        if imgtype == 'image':
            d.appendVarFlag('do_unpack', 'depends', ' ' + image + ':do_image_complete')
        else:
            d.appendVarFlag('do_unpack', 'depends', ' ' + image + ':do_deploy')
}

S = "${WORKDIR}"
B = "${WORKDIR}/build"
BUNDLE_DIR = "${S}/bundle"

RAUC_KEY_FILE ??= ""
RAUC_KEY_FILE[doc] = "Specifies the path to the RAUC key file used for signing. Use COREBASE to reference files located in any shared BSP folder."
RAUC_CERT_FILE ??= ""
RAUC_CERT_FILE[doc] = "Specifies the path to the RAUC cert file used for signing. Use COREBASE to reference files located in any shared BSP folder."

DEPENDS = "rauc-native squashfs-tools-native"

def write_manifest(d):
    import shutil

    machine = d.getVar('MACHINE')
    img_fstype = d.getVar('RAUC_IMAGE_FSTYPE')
    bundle_path = d.expand("${BUNDLE_DIR}")

    bb.utils.mkdirhier(bundle_path)
    try:
        manifest = open('%s/manifest.raucm' % bundle_path, 'w')
    except OSError:
        raise bb.build.FuncFailed('Unable to open manifest.raucm')

    manifest.write('[update]\n')
    manifest.write(d.expand('compatible=${RAUC_BUNDLE_COMPATIBLE}\n'))
    manifest.write(d.expand('version=${RAUC_BUNDLE_VERSION}\n'))
    manifest.write(d.expand('description=${RAUC_BUNDLE_DESCRIPTION}\n'))
    manifest.write(d.expand('build=${RAUC_BUNDLE_BUILD}\n'))
    manifest.write('\n')

    hooksflags = d.getVarFlags('RAUC_BUNDLE_HOOKS')
    if hooksflags and 'file' in hooksflags:
        manifest.write('[hooks]\n')
        manifest.write("filename=%s\n" % hooksflags.get('file'))
        if 'hooks' in hooksflags:
            manifest.write("hooks=%s\n" % hooksflags.get('hooks'))
        manifest.write('\n')

    for slot in (d.getVar('RAUC_BUNDLE_SLOTS') or "").split():
        slotflags = d.getVarFlags('RAUC_SLOT_%s' % slot)
        if slotflags and 'name' in slotflags:
            slotname = slotflags.get('name')
        else:
            slotname = slot
        manifest.write('[image.%s]\n' % slotname)
        if slotflags and 'type' in slotflags:
            imgtype = slotflags.get('type')
        else:
            imgtype = 'image'

        if slotflags and 'fstype' in slotflags:
            img_fstype = slotflags.get('fstype')

        if imgtype == 'image':
            if slotflags and 'file' in slotflags:
                imgsource = d.getVarFlag('RAUC_SLOT_%s' % slot, 'file')
            else:
                imgsource = "%s-%s.%s" % (d.getVar('RAUC_SLOT_%s' % slot), machine, img_fstype)
            imgname = imgsource
        elif imgtype == 'kernel':
            # TODO: Add image type support
            if slotflags and 'file' in slotflags:
                imgsource = d.getVarFlag('RAUC_SLOT_%s' % slot, 'file')
            else:
                imgsource = "%s-%s.bin" % ("zImage", machine)
            imgname = "%s.%s" % (imgsource, "img")
        elif imgtype == 'boot':
            if slotflags and 'file' in slotflags:
                imgsource = d.getVarFlag('RAUC_SLOT_%s' % slot, 'file')
            else:
                imgsource = "%s" % ("barebox.img")
            imgname = imgsource
        elif imgtype == 'file':
            if slotflags and 'file' in slotflags:
                imgsource = d.getVarFlag('RAUC_SLOT_%s' % slot, 'file')
            else:
                raise bb.build.FuncFailed('Unknown file for slot: %s' % slot)
            imgname = "%s.%s" % (imgsource, "img")
        else:
            raise bb.build.FuncFailed('Unknown image type: %s' % imgtype)

        print(imgname)
        manifest.write("filename=%s\n" % imgname)
        if slotflags and 'hooks' in slotflags:
            manifest.write("hooks=%s\n" % slotflags.get('hooks'))
        manifest.write("\n")

        bundle_imgpath = "%s/%s" % (bundle_path, imgname)
        # Set or update symlinks to image files
        if os.path.lexists(bundle_imgpath):
            bb.utils.remove(bundle_imgpath)
        shutil.copy(d.expand("${DEPLOY_DIR_IMAGE}/%s") % imgsource, bundle_imgpath)
        if not os.path.exists(bundle_imgpath):
            raise bb.build.FuncFailed('Failed creating symlink to %s' % imgname)

    manifest.close()

do_unpack_append() {
    import shutil
    import os
    import stat

    write_manifest(d)

    hooksflags = d.getVarFlags('RAUC_BUNDLE_HOOKS')
    if hooksflags and 'file' in hooksflags:
        hf = hooksflags.get('file')
        dsthook = d.expand("${BUNDLE_DIR}/%s" % hf)
        shutil.copy(d.expand("${WORKDIR}/%s" % hf), dsthook)
        st = os.stat(dsthook)
        os.chmod(dsthook, st.st_mode | stat.S_IEXEC)
}

BUNDLE_BASENAME ??= "${PN}"
BUNDLE_BASENAME[doc] = "Specifies desired output base name of generated bundle."
BUNDLE_NAME ??= "${BUNDLE_BASENAME}-${MACHINE}-${DATETIME}"
BUNDLE_NAME[doc] = "Specifies desired full output name of generated bundle."
# Don't include the DATETIME variable in the sstate package sigantures
BUNDLE_NAME[vardepsexclude] = "DATETIME"
BUNDLE_LINK_NAME ??= "${BUNDLE_BASENAME}-${MACHINE}"

do_bundle() {
	if [ -z "${RAUC_KEY_FILE}" ]; then
		bbfatal "'RAUC_KEY_FILE' not set. Please set to a valid key file location."
	fi

	if [ -z "${RAUC_CERT_FILE}" ]; then
		bbfatal "'RAUC_CERT_FILE' not set. Please set to a valid certificate file location."
	fi

	if [ -e ${B}/bundle.raucb ]; then
		rm ${B}/bundle.raucb
	fi
	${STAGING_DIR_NATIVE}${bindir}/rauc bundle \
		--debug \
		--cert="${RAUC_CERT_FILE}" \
		--key="${RAUC_KEY_FILE}" \
		${BUNDLE_DIR} \
		${B}/bundle.raucb
}
do_bundle[dirs] = "${B}"

addtask bundle after do_configure before do_build

inherit deploy

do_deploy() {
	install -d ${DEPLOYDIR}
	install ${B}/bundle.raucb ${DEPLOYDIR}/${BUNDLE_NAME}.raucb
	ln -sf ${BUNDLE_NAME}.raucb ${DEPLOYDIR}/${BUNDLE_LINK_NAME}.raucb
}

addtask deploy after do_bundle before do_build

do_deploy[cleandirs] = "${DEPLOYDIR}"
