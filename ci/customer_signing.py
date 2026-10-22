"""Restore an encrypted keystore from Actions Secrets and verify public certificates.
Never prints passwords, keystore bytes or base64. Uses only the Python standard library.
"""
import argparse
import base64
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys

ALIAS = 'fazaa-customer'
PACKAGE = 'com.fazaa.customer.test'


def expected_fingerprint():
    raw = os.environ.get('FAZAA_CUSTOMER_CERT_SHA256', '')
    value = re.sub(r'[\s:]', '', raw).upper()
    if not re.fullmatch(r'[A-F0-9]{64}', value):
        raise ValueError('FAZAA_CUSTOMER_CERT_SHA256 must contain the certificate SHA-256 fingerprint')
    return value


def quiet_run(args):
    result = subprocess.run(args, capture_output=True, text=True, check=False)
    if result.returncode:
        # Tool stderr is intentionally not echoed: it can include paths or environment details.
        raise ValueError('Signing tool failed; check key alias, password and file format')
    return result.stdout


def restore(directory):
    encoded = os.environ.get('FAZAA_CUSTOMER_KEYSTORE_BASE64', '')
    password = os.environ.get('FAZAA_KEYSTORE_PASSWORD', '')
    expected_fingerprint()
    if len(password) < 24 or not password.isascii() or password != password.strip():
        raise ValueError('A signing password of at least 24 ASCII characters, without surrounding spaces, is required')
    compact = re.sub(r'\s', '', encoded)
    if not compact or len(compact) > 60000:
        raise ValueError('Missing or oversized keystore secret')
    try:
        data = base64.b64decode(compact, validate=True)
    except (ValueError, base64.binascii.Error):
        raise ValueError('Keystore secret is not valid base64') from None
    if not 512 <= len(data) <= 40000:
        raise ValueError('Unexpected keystore size')
    directory = Path(directory)
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(directory, 0o700)
    key = directory / 'customer.p12'
    # Refuse to overwrite any prior key, including a symlink.
    with key.open('xb') as stream:
        os.chmod(key, 0o600)
        stream.write(data)
    return key


def verify_keystore(key, keytool='keytool'):
    key = Path(key)
    certificate = key.parent / 'customer-signing-cert.der'
    quiet_run([keytool, '-exportcert', '-alias', ALIAS, '-keystore', str(key),
               '-storetype', 'PKCS12', '-storepass:env', 'FAZAA_KEYSTORE_PASSWORD',
               '-file', str(certificate)])
    fingerprint = hashlib.sha256(certificate.read_bytes()).hexdigest().upper()
    if fingerprint != expected_fingerprint():
        raise ValueError('Certificate fingerprint mismatch; refusing to use a different signing identity')
    listing = quiet_run([keytool, '-J-Duser.language=en', '-list', '-v', '-alias', ALIAS,
                         '-keystore', str(key), '-storetype', 'PKCS12',
                         '-storepass:env', 'FAZAA_KEYSTORE_PASSWORD'])
    if 'PrivateKeyEntry' not in listing:
        raise ValueError('The keystore must contain the customer private signing key')
    return fingerprint


def verify_apk(apk, apksigner, aapt, version):
    result = quiet_run([apksigner, 'verify', '--verbose', '--print-certs', str(apk)])
    fingerprints = re.findall(r'Signer #\d+ certificate SHA-256 digest:\s*([a-fA-F0-9:]+)', result)
    if len(fingerprints) != 1 or fingerprints[0].replace(':', '').upper() != expected_fingerprint():
        raise ValueError('APK certificate does not match the fixed customer signing certificate')
    badging = quiet_run([aapt, 'dump', 'badging', str(apk)])
    match = re.search(r"^package: name='([^']+)' versionCode='([0-9]+)'", badging, re.M)
    if not match or match[1] != PACKAGE or int(match[2]) != int(version):
        raise ValueError('APK package or version code does not match this customer build')
    if re.search(r'^application-debuggable', badging, re.M):
        raise ValueError('Refusing to publish a debuggable APK as the signed customer release')
    return hashlib.sha256(Path(apk).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('restore').add_argument('directory')
    sub.add_parser('verify-keystore').add_argument('key')
    apk = sub.add_parser('verify-apk')
    apk.add_argument('apk'); apk.add_argument('apksigner'); apk.add_argument('aapt'); apk.add_argument('version')
    args = parser.parse_args()
    if args.command == 'restore':
        key = restore(args.directory)
        verify_keystore(key)
        # Only a non-secret runner-local path is persisted; no password goes into GITHUB_ENV.
        with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream:
            stream.write('FAZAA_KEYSTORE_FILE=' + str(key) + '\n')
        print('Stable customer signing material restored and certificate verified.')
    elif args.command == 'verify-keystore':
        print('Verified public certificate SHA-256: ' + verify_keystore(args.key))
    else:
        digest = verify_apk(args.apk, args.apksigner, args.aapt, args.version)
        print('Signed non-debuggable customer APK verified. APK SHA-256: ' + digest)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError) as error:
        print('Customer signing check failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
