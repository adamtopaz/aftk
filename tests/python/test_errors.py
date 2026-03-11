from __future__ import annotations

import unittest

from aftk_client.errors import (
    DomainConflictError,
    DomainNotFoundError,
    DomainOperationError,
    DomainValidationError,
    InvalidParamsError,
    jsonrpc_error_from_response,
)


class ErrorTests(unittest.TestCase):
    def test_domain_error_mapping_preserves_structured_data(self) -> None:
        err = jsonrpc_error_from_response(
            code=-32020,
            message="missing node",
            data={
                "layer": "knowledgebase",
                "code": "node.notFound",
                "message": "missing node",
                "exitCode": 3,
            },
            method="knowledgebase_show",
            request_id=7,
        )
        self.assertIsInstance(err, DomainNotFoundError)
        assert isinstance(err, DomainNotFoundError)
        self.assertIsNotNone(err.domain)
        assert err.domain is not None
        self.assertEqual(err.domain.layer, "knowledgebase")
        self.assertEqual(err.domain.code, "node.notFound")
        self.assertEqual(err.domain.exit_code, 3)

    def test_other_domain_error_codes_map_to_specific_exceptions(self) -> None:
        validation = jsonrpc_error_from_response(
            code=-32021,
            message="bad metadata",
            data=None,
            method="knowledgebase_replace_metadata",
            request_id=1,
        )
        conflict = jsonrpc_error_from_response(
            code=-32022,
            message="already exists",
            data=None,
            method="knowledgebase_create",
            request_id=2,
        )
        operation = jsonrpc_error_from_response(
            code=-32023,
            message="generic domain failure",
            data=None,
            method="informal_present",
            request_id=3,
        )
        invalid = jsonrpc_error_from_response(
            code=-32602,
            message="Invalid params",
            data="bad request",
            method="informal_status",
            request_id=4,
        )

        self.assertIsInstance(validation, DomainValidationError)
        self.assertIsInstance(conflict, DomainConflictError)
        self.assertIsInstance(operation, DomainOperationError)
        self.assertIsInstance(invalid, InvalidParamsError)


if __name__ == "__main__":
    unittest.main()
