FILESEXTRAPATHS_prepend := "${THISDIR}/${PN}:"

SRC_URI_append_connagtive-productive = " \
    file://0001-include-configs-Change-A-B-system-partitions.patch \
    file://0002-include-configs-Enable-booting-A-B-system-by-default.patch \
"
