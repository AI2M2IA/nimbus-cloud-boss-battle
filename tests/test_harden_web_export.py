import unittest

from scripts.dev.harden_web_export import DESCRIPTION, FALLBACK, harden


class HardenWebExportTest(unittest.TestCase):
    def test_hardens_current_godot_template_shape(self):
        source = (
            '<meta name="viewport" content="width=device-width, '
            'user-scalable=no, initial-scale=1.0">'
            '<canvas id="canvas">Your browser does not support the canvas tag.</canvas>'
        )
        result = harden(source)
        self.assertNotIn("user-scalable=no", result)
        self.assertIn("user-scalable=yes, maximum-scale=5", result)
        self.assertIn(DESCRIPTION, result)
        self.assertIn(FALLBACK, result)
        self.assertIn('role="application"', result)

    def test_fails_closed_when_godot_template_drifts(self):
        with self.assertRaises(ValueError):
            harden('<meta name="viewport" content="width=device-width">')


if __name__ == "__main__":
    unittest.main()
