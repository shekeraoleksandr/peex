import json
import os
import unittest

import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app"))
import calc  # noqa: E402


class TestCalc(unittest.TestCase):
    def test_add(self):
        self.assertEqual(calc.add(2, 3), 5)

    def test_mul(self):
        self.assertEqual(calc.mul(4, 5), 20)

    def test_discount(self):
        self.assertEqual(calc.discount(100, 20), 80.0)

    def test_discount_bounds(self):
        with self.assertRaises(ValueError):
            calc.discount(100, 150)


class TestConfig(unittest.TestCase):
    def test_config_valid(self):
        path = os.path.join(os.path.dirname(__file__), "..", "config", "app.config.json")
        with open(path, encoding="utf-8") as fh:
            cfg = json.load(fh)
        for key in ("name", "version", "environment"):
            self.assertIn(key, cfg)


if __name__ == "__main__":
    unittest.main(verbosity=2)
