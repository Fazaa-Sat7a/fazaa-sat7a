"""Use a throwaway local key to test the actual helper. Never uses the user's key."""
import base64
import hashlib
import importlib.util
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('driver_signing', ROOT / 'ci/driver_signing.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class SigningChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = tempfile.TemporaryDirectory(prefix='fazaa-signing-test-')
        cls.directory = Path(cls.folder.name)
        cls.password = secrets.token_urlsafe(32)
        cls.keytool = shutil.which('keytool')
        if not cls.keytool:
            raise unittest.SkipTest('JDK keytool is required')
        env = dict(os.environ, FAZAA_TEST_PASSWORD=cls.password)
        cls.key = cls.directory / 'test.p12'
        created = subprocess.run([cls.keytool, '-genkeypair', '-keystore', str(cls.key), '-storetype', 'PKCS12',
            '-alias', 'fazaa-driver', '-keyalg', 'RSA', '-keysize', '3072', '-sigalg', 'SHA256withRSA',
            '-validity', '10000', '-dname', 'CN=Fazaa Signing Test', '-storepass:env', 'FAZAA_TEST_PASSWORD',
            '-keypass:env', 'FAZAA_TEST_PASSWORD', '-noprompt'], env=env, capture_output=True)
        if created.returncode:
            raise RuntimeError('Test key generation failed')
        cert = cls.directory / 'test-cert.der'
        exported = subprocess.run([cls.keytool, '-exportcert', '-keystore', str(cls.key), '-alias', 'fazaa-driver',
            '-storepass:env', 'FAZAA_TEST_PASSWORD', '-file', str(cert)], env=env, capture_output=True)
        if exported.returncode:
            raise RuntimeError('Test certificate export failed')
        cls.fingerprint = hashlib.sha256(cert.read_bytes()).hexdigest().upper()
        cls.values = {'FAZAA_DRIVER_KEYSTORE_BASE64': base64.b64encode(cls.key.read_bytes()).decode(),
                      'FAZAA_DRIVER_KEYSTORE_PASSWORD': cls.password, 'FAZAA_DRIVER_CERT_SHA256': cls.fingerprint}

    @classmethod
    def tearDownClass(cls):
        cls.folder.cleanup()

    def test_real_restore_and_private_key_certificate(self):
        with tempfile.TemporaryDirectory() as target, patch.dict(os.environ, self.values):
            restored = module.restore(target)
            self.assertEqual(restored.read_bytes(), self.key.read_bytes())
            self.assertEqual(module.verify_keystore(restored, self.keytool), self.fingerprint)
            self.assertEqual(restored.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                module.restore(target)

    def test_certificate_drift_and_wrong_password_are_rejected(self):
        with tempfile.TemporaryDirectory() as target, patch.dict(os.environ, self.values):
            restored = module.restore(target)
            with patch.dict(os.environ, {'FAZAA_DRIVER_CERT_SHA256': '0' * 64}):
                with self.assertRaisesRegex(ValueError, 'fingerprint mismatch'):
                    module.verify_keystore(restored, self.keytool)
            with patch.dict(os.environ, {'FAZAA_DRIVER_KEYSTORE_PASSWORD': 'not-the-right-password-at-all'}):
                with self.assertRaisesRegex(ValueError, 'Signing tool failed'):
                    module.verify_keystore(restored, self.keytool)

    def test_missing_secret_and_invalid_base64_fail_closed(self):
        with tempfile.TemporaryDirectory() as target, patch.dict(os.environ, self.values):
            with patch.dict(os.environ, {'FAZAA_DRIVER_KEYSTORE_BASE64': ''}):
                with self.assertRaises(ValueError): module.restore(target)
            with patch.dict(os.environ, {'FAZAA_DRIVER_KEYSTORE_BASE64': 'not base64!'}):
                with self.assertRaises(ValueError): module.restore(target)
            with patch.dict(os.environ, {'FAZAA_DRIVER_KEYSTORE_PASSWORD': 'short'}):
                with self.assertRaises(ValueError): module.restore(target)

    def test_apk_gate_checks_cert_package_version_and_debug_flag(self):
        good = 'Signer #1 certificate SHA-256 digest: ' + self.fingerprint.lower()
        package = "package: name='com.fazaa.driver.test' versionCode='1004' versionName='0.2.1'\n"
        with patch.dict(os.environ, self.values), patch.object(module, 'quiet_run', side_effect=[good, package]):
            result = module.verify_apk(self.key, 'apksigner', 'aapt', '1004')
            self.assertEqual(result, hashlib.sha256(self.key.read_bytes()).hexdigest())
        for certificate, badging, version in [
            ('Signer #1 certificate SHA-256 digest: ' + '0'*64, package, '1004'),
            (good, package.replace('driver.test', 'customer.test'), '1004'),
            (good, package, '1005'),
            (good, package + 'application-debuggable\n', '1004')]:
            with patch.dict(os.environ, self.values), patch.object(module, 'quiet_run', side_effect=[certificate, badging]):
                with self.assertRaises(ValueError): module.verify_apk(self.key, 'apksigner', 'aapt', version)

if __name__ == '__main__':
    unittest.main()
