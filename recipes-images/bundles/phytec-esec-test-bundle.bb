require recipes-images/bundles/phytec-base-bundle.inc

RAUC_SLOT_rootfs = "phytec-esec-test-image"

RAUC_KEY_FILE = "${OEROOT}/../meta-esec-iotdm/openssl-ca/rauc/private/production-1.key.pem"
RAUC_CERT_FILE = "${OEROOT}/../meta-esec-iotdm/openssl-ca/rauc/production-1.cert.pem"
