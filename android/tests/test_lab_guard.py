import unittest
from unittest.mock import patch, call
import lab_ui

class GuardTest(unittest.TestCase):
    def test_wrong_avd_never_dispatches_reboot(self):
        with patch.object(lab_ui,'raw',return_value='UnrelatedDevice\nOK') as raw:
            with self.assertRaises(RuntimeError):lab_ui.adb('reboot')
            self.assertEqual(raw.call_args_list,[call('emu','avd','name')])
    def test_missing_app_never_dispatches_setting_write(self):
        with patch.object(lab_ui,'raw',side_effect=['BlinkLink16\nOK','1','']) as raw:
            with self.assertRaises(RuntimeError):lab_ui.adb('shell','settings','put','global','adb_wifi_enabled','1')
            self.assertEqual(raw.call_count,3)
    def test_correct_target_dispatches(self):
        with patch.object(lab_ui,'raw',side_effect=['BlinkLink16\nOK','1','package:/app/base.apk','OK']) as raw:
            self.assertEqual(lab_ui.adb('shell','echo','OK'),'OK')
            self.assertEqual(raw.call_args,call('shell','echo','OK'))
if __name__=='__main__':unittest.main()
