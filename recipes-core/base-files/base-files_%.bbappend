FILESEXTRAPATHS_prepend := "${THISDIR}/${BPN}:"

SRC_URI_append_connagtive-productive = " \
    file://welcome-connagtive.sh \
"

dirs755_append_connagtive-productive = " ${sysconfdir}/profile.d"

do_configure_append_connagtive-productive() {
    printf "
/dev/mmcblk2p3  /mnt/config  auto  defaults  0  0
/dev/appfs      /mnt/app     auto  defaults  0  0
" >> ${S}/fstab
}

do_install_append_connagtive-productive() {
    install -m 0755 ${WORKDIR}/welcome-connagtive.sh ${D}${sysconfdir}/profile.d/welcome-connagtive.sh
}
