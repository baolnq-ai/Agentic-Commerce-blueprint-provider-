from src.merchant.services.post_purchase import (
    _extract_json_object as extract_post_purchase_json,
)
from src.merchant.services.promotion import (
    _extract_json_object as extract_promotion_json,
)


def test_promotion_parser_handles_plain_json() -> None:
    payload = '{"action":"DISCOUNT_10_PCT","reasoning":"Inventory is high"}'

    parsed = extract_promotion_json(payload)

    assert parsed == {
        "action": "DISCOUNT_10_PCT",
        "reasoning": "Inventory is high",
    }


def test_promotion_parser_extracts_embedded_json_object() -> None:
    payload = """
    Sure, here is the decision:

    ```json
    {"action":"FREE_SHIPPING","reason_codes":["NEW_ARRIVAL"]}
    ```

    Thanks!
    """

    parsed = extract_promotion_json(payload)

    assert parsed == {
        "action": "FREE_SHIPPING",
        "reason_codes": ["NEW_ARRIVAL"],
    }


def test_post_purchase_parser_extracts_json_from_wrapped_response() -> None:
    payload = """
    {
      "status": "order_confirmed",
      "language": "en",
      "subject": "Order confirmed",
      "message": "Your order is on the way."
    }

    Let me know if you need anything else.
    """

    parsed = extract_post_purchase_json(payload)

    assert parsed == {
        "status": "order_confirmed",
        "language": "en",
        "subject": "Order confirmed",
        "message": "Your order is on the way.",
    }


def test_post_purchase_parser_returns_none_when_no_json_exists() -> None:
    assert extract_post_purchase_json("No structured payload available.") is None
