#!/usr/bin/env bash
#===============================================================================
#
#  provision-tpm.sh
#
#  Copyright (C) 2021 by PHYTEC Messtechnik GmbH
#  All rights reserved.
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2 as published by
#  the Free Software Foundation.
#
#===============================================================================

printf "======================================\n" > /dev/console
printf "PHYTEC TPM2 Test Provision Version 0.2\n" > /dev/console
printf "======================================\n" > /dev/console

USEHSM=1
CA_P12=""
CA_ROOT=""
HSMCERT_LABEL=""
HSM_USER_PIN=""
while getopts 'ht:l:r:P:' arg ; do
    case "$arg" in
    h)  printf "h  Show this help \n" > /dev/console
        printf "t  Path to the PKCS#12 container with CA and private Key\n" > /dev/console
        printf "l  Label for Cert and Key in HSM\n" > /dev/console
        printf "P  HSM User Pin\n" > /dev/console
        printf "r  Path to Root CA\n" > /dev/console
        exit 2
        ;;
    t)
        USEHSM=0
        CA_P12=${OPTARG}
        ;;
    l)
        USEHSM=1
        HSMCERT_LABEL=${OPTARG}
        ;;
    r)
        CA_ROOT=${OPTARG}
        ;;
    P)
        HSM_USER_PIN=${OPTARG}
        ;;
    esac
done
export CA_ROOT
export CA_P12
export HSMCERT_LABEL

# Get CPU UID
get_cpu_uid() {
    val=$(cat /sys/devices/soc0/soc_uid)
    echo "${val}"
}

set -e
trap end EXIT
end() {
    if [ "$?" -ne 0 ]; then
        printf "PHYTEC-TPM2-Provision:fail! \n" > /dev/console
    fi
}

# Variable declaration
CA_DIR=`mktemp -d -t tpm2tmpca.XXXXXX`
export CA_DIR

tpm2pkcs11tool='pkcs11-tool --module /usr/lib/libtpm2_pkcs11.so.0'
hsmpkcs11tool='pkcs11-tool --module /usr/lib/opensc-pkcs11.so'

# Generate SO-PIN
TPM_SOPIN=$(tpm2_getrandom --hex 8 | tr -dc 0-9)
TPM_PIN=$(get_cpu_uid | head -c 7)

# Create Dev UID
setup_devuid() {
    read_ekcerttpm
    ekid=$(get_serial_ekcert)
    randid=$(tpm2_getrandom --hex 2)
    export DEV_UID="${ekid}${randid}"
}

# Create Device Common Name
setup_devcn() {
    val=$(cat /proc/device-tree/model | cut -d ' ' -f 2)
    export DEV_CN="${val}-${DEV_UID}"
}

# Init Root Certificate
setup_caroot() {
    export ROOTCA_PEM="${CA_DIR}/rootca.pem"
    if [ $USEHSM -eq 0 ] && [ -f "${CA_ROOT}" ]; then
        cp ${CA_ROOT} ${ROOTCA_PEM}
    elif [ $USEHSM -eq 1 ]; then
        $hsmpkcs11tool -r -y cert -a "${HSMCERT_LABEL}root" -o ${CA_DIR}/rootca.der
        openssl x509 -inform DER -in ${CA_DIR}/rootca.der -outform PEM -out ${ROOTCA_PEM}
    else
        exit 5
    fi
}
# With Testing Intermediate CA from PKCS#12 container
setup_casub() {
    export CA_PEM="${CA_DIR}/subca.pem"
    if [ $USEHSM -eq 0 ] && [ -f "${CA_P12}" ]; then
        export CA_KEY="${CA_DIR}/subca.key"
        # Extract CA
        openssl pkcs12 -in "${CA_P12}" -out "${CA_PEM}" -clcerts -nokeys
        # Extract Keys
        openssl pkcs12 -in "${CA_P12}" -out "${CA_KEY}" -nocerts -nodes
    elif [ $USEHSM -eq 1 ]; then
        $hsmpkcs11tool -r -y cert -a ${HSMCERT_LABEL} -o ${CA_DIR}/subca.der
        openssl x509 -inform DER -in ${CA_DIR}/subca.der -outform PEM -out ${CA_PEM}
    else
        exit 4
    fi
    # make the DB
    touch "${CA_DIR}"/index.txt
    touch "${CA_DIR}"/index.txt.attr

    echo "${DEV_UID}" > "${CA_DIR}"/serial

    LINEPRIVKEY=""
    if [ ${USEHSM} -eq 0 ]; then
        LINEPRIVKEY="private_key      = ${CA_KEY}"
    fi
cat > ${CA_DIR}/ssl.cnf <<EOF
openssl_conf = openssl_init

[openssl_init]
engines = engine_section

[ default ]
ca               = x_ca
dir              = .

[ca]
default_ca       = x_ca

[x_ca]
dir              = ${CA_DIR}
database         = ${CA_DIR}/index.txt
new_certs_dir    = ${CA_DIR}
serial           = ${CA_DIR}/serial
certificate      = ${CA_PEM}
default_days     = 32850
default_md       = sha256
policy           = policy_any
x509_extensions  = v3_client
string_mask      = utf8only
${LINEPRIVKEY}

[ policy_any ]
commonName          = supplied
organizationName    = match
localityName        = match
countryName         = match
stateOrProvinceName = match

[ v3_client ]
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid:always,issuer
basicConstraints        = critical, CA:false
keyUsage                = critical, digitalSignature, keyAgreement
extendedKeyUsage        = critical, clientAuth
authorityInfoAccess     = OCSP;URI:http://ocsp.testing.aws.esec-experts.com

[ engine_section ]
pkcs11  = pkcs11_section

[ pkcs11_section ]
engine_id       = pkcs11
MODULE_PATH     = /usr/lib/opensc-pkcs11.so
init            = 0
EOF
}

# Create openssl conf for CSR creation
create_csrconf() {
cat > ${CA_DIR}/csrtpm.cnf <<EOF
openssl_conf = openssl_init

[openssl_init]
engines = engine_section

[engine_section]
pkcs11 = pkcs11_section

[pkcs11_section]
engine_id = pkcs11
MODULE_PATH = /usr/lib/libtpm2_pkcs11.so.0
PIN=myuserpin
init = 0

[ req ]
prompt              = no
distinguished_name  = req_dn
string_mask         = nombstr

[ req_dn ]
CN  = ${DEV_CN}
C   = DE
ST  = Rheinland-Pfalz
L   = Mainz
O   = PHYTEC
EOF
}

# Read EK Cert from TPM
read_ekcerttpm() {
    export CA_EKCERT="${CA_DIR}/ek_cert.pem"
    RSA_EK_CERT_NV_INDEX=0x01C00002
    NV_SIZE=`tpm2_nvreadpublic ${RSA_EK_CERT_NV_INDEX} | grep size | awk ' {print $2}'`
    tpm2_nvread --hierarchy owner --size ${NV_SIZE} --output ${CA_EKCERT}.der ${RSA_EK_CERT_NV_INDEX}
    openssl x509 -inform DER -outform PEM -text -in ${CA_EKCERT}.der -out ${CA_EKCERT}
}

# Get Serial Number from CERT
get_serial_ekcert() {
    val=$(openssl x509 -noout -serial -in "${CA_EKCERT}" | cut -d'=' -f2)
    echo "${val}"
}

setup_devuid
setup_devcn
# Create Sub-CA
setup_casub
# Create Root CA
setup_caroot
# Create CSR Conf
create_csrconf

# make path for tpm2-pkcs11 metadata
mkdir -p /mnt/config/tpm2/pkcs11

# TPM Remote Attestation
tss2_provision

# Init Token for Device Certificate
$tpm2pkcs11tool --init-token --label=iotdm --so-pin=${TPM_SOPIN}
# Set user pin
$tpm2pkcs11tool --label="iotdm" --init-pin --so-pin ${TPM_SOPIN} --pin ${TPM_PIN}
# Create Keypair for Device Certificate
$tpm2pkcs11tool --label="iotdm-keypair" --login --pin=${TPM_PIN} --keypairgen --usage-sign --key-type EC:prime256v1 -d 1
# Create CSR
openssl req -config ${CA_DIR}/csrtpm.cnf -new -engine pkcs11 -keyform engine -key "pkcs11:model=SLB9670;manufacturer=Infineon;token=iotdm;object=iotdm-keypair;type=private;pin-value=${TPM_PIN}" -out "${CA_DIR}/devcsr.pem"
# Create Device Cert
if [ $USEHSM -eq 1 ]; then
    openssl ca -config ${CA_DIR}/ssl.cnf -batch -engine pkcs11 -keyform engine -keyfile "slot_0-label_${HSMCERT_LABEL}" -in "${CA_DIR}/devcsr.pem" -out "${CA_DIR}/devcrt.pem" -passin pass:${HSM_USER_PIN}
else
    openssl ca -config ${CA_DIR}/ssl.cnf -batch -in ${CA_DIR}/devcsr.pem -out "${CA_DIR}/devcrt.pem"
fi
#Write Device Cert
#p11tool --login --write --load-certificate="${CA_DIR}/devcrt.pem" --label=iotdm-cert "pkcs11:model=SLB9670;manufacturer=Infineon;token=iotdm;pin-value=${TPM_PIN}"
$tpm2pkcs11tool -w "${CA_DIR}/devcrt.pem" -y cert -a iotdm-cert --pin ${TPM_PIN} -d 2
# Write Sub CA Cert
#p11tool --login --write --load-certificate="${CA_PEM}" --ca --label=iotdm-subcert "pkcs11:model=SLB9670;manufacturer=Infineon;token=iotdm;pin-value=${TPM_PIN}"
$tpm2pkcs11tool -w "${CA_PEM}" -y cert -a iotdm-subcert --pin ${TPM_PIN} -d 3
# Write root CA cert
#p11tool --login --write --load-certificate="${ROOTCA_PEM}" --ca --label=iotdm-rootcert "pkcs11:model=SLB9670;manufacturer=Infineon;token=iotdm;pin-value=${TPM_PIN}"
$tpm2pkcs11tool -w "${ROOTCA_PEM}" -y cert -a iotdm-rootcert --pin ${TPM_PIN} -d 4
printf "PHYTEC-TPM2-Provision:pass! \n" > /dev/console
