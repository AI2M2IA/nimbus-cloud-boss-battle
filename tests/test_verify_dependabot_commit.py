import copy
import unittest

from scripts.dev.verify_dependabot_commit import is_verified_dependabot_commit


SHA = "f15c5594785547fc18aa81bfff29c6b76b7fde0d"


def verified_record():
    return {
        "sha": SHA,
        "author": {"login": "dependabot[bot]", "id": 49699333},
        "committer": {"login": "web-flow", "id": 19864447},
        "commit": {
            "author": {
                "name": "dependabot[bot]",
                "email": "49699333+dependabot[bot]@users.noreply.github.com",
            },
            "committer": {"name": "GitHub", "email": "noreply@github.com"},
            "verification": {"verified": True, "reason": "valid"},
        },
    }


class VerifiedDependabotCommitTests(unittest.TestCase):
    def test_accepts_exact_verified_record(self):
        self.assertTrue(is_verified_dependabot_commit(verified_record(), SHA))

    def test_rejects_wrong_sha(self):
        self.assertFalse(is_verified_dependabot_commit(verified_record(), "0" * 40))

    def test_rejects_lookalike_actor(self):
        record = copy.deepcopy(verified_record())
        record["author"]["id"] = 1
        self.assertFalse(is_verified_dependabot_commit(record, SHA))

    def test_rejects_unverified_signature(self):
        record = copy.deepcopy(verified_record())
        record["commit"]["verification"] = {"verified": False, "reason": "unsigned"}
        self.assertFalse(is_verified_dependabot_commit(record, SHA))

    def test_rejects_incomplete_or_invalid_payload(self):
        self.assertFalse(is_verified_dependabot_commit({}, SHA))
        self.assertFalse(is_verified_dependabot_commit([], SHA))


if __name__ == "__main__":
    unittest.main()
