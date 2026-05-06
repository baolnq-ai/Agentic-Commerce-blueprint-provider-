# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
Search products tool for the MCP server.

This module provides the search_products MCP tool which serves as the
entry point for widget discovery per the Apps SDK spec.

This module delegates search entirely to the NAT RAG search agent and
enriches results from the merchant API - no hardcoded product data.
"""

from __future__ import annotations

import json
import logging
import os
from typing import Any, cast

import httpx

from src.apps_sdk.config import get_apps_sdk_settings

logger = logging.getLogger(__name__)

settings = get_apps_sdk_settings()
SEARCH_AGENT_URL = settings.search_agent_url
MERCHANT_API_URL = settings.merchant_api_url
SEARCH_MIN_SIMILARITY = settings.search_min_similarity
SEARCH_DISTANCE_CUTOFF = settings.search_distance_cutoff
NIM_EMBED_MODEL = os.environ.get("NIM_EMBED_MODEL_NAME", "nvidia/nv-embedqa-e5-v5")
NIM_LLM_MODEL = os.environ.get("NIM_LLM_MODEL_NAME", "nvidia/llama-3.1-nemotron-nano-8b-v1")
NIM_LLM_BASE_URL = os.environ.get("NIM_LLM_BASE_URL", "https://integrate.api.nvidia.com/v1")
NVIDIA_API_KEY = os.environ.get("NVIDIA_API_KEY", "")
NIM_RUN_MODE = os.environ.get("NIM_RUN_MODE", "api")

DEFAULT_USER = {
    "id": "user_demo123",
    "name": "John Doe",
    "email": "john@example.com",
    "loyaltyPoints": 1250,
    "tier": "Gold",
    "memberSince": "2024-03-15",
}


def _error_search_response(
    query: str,
    category: str | None,
    message: str,
) -> dict[str, Any]:
    return {
        "products": [],
        "query": query,
        "category": category,
        "totalResults": 0,
        "error": message,
        "user": DEFAULT_USER,
        "theme": "dark",
        "locale": "en-US",
        "agent_mode": "llm",
        "agent_model": NIM_LLM_MODEL,
        "nim_mode": NIM_RUN_MODE,
        "agent_activity": message,
        "_meta": {
            "openai/outputTemplate": "ui://widget/merchant-app.html",
            "openai/toolInvocation/invoking": "Searching products...",
            "openai/toolInvocation/invoked": message,
            "openai/widgetAccessible": True,
        },
    }


def _extract_similarity(item: dict[str, Any]) -> float | None:
    similarity = item.get("similarity")
    if isinstance(similarity, (int, float)):
        return float(similarity)

    score = item.get("score")
    if isinstance(score, (int, float)):
        return 1 / (1 + float(score))

    distance = item.get("distance")
    if isinstance(distance, (int, float)):
        return 1 / (1 + float(distance))

    return None


def _extract_distance(item: dict[str, Any]) -> float | None:
    distance = item.get("distance")
    if isinstance(distance, (int, float)):
        return float(distance)
    return None


def _parse_search_agent_response(raw_result: Any) -> dict[str, Any]:
    """Parse the search agent response into a typed dictionary."""
    parsed: dict[str, Any] = {}

    if isinstance(raw_result, dict):
        raw_dict = cast(dict[str, Any], raw_result)
        value = raw_dict.get("value")
        if isinstance(value, str):
            loaded = json.loads(value)
            if isinstance(loaded, dict):
                parsed = cast(dict[str, Any], loaded)
        elif isinstance(value, dict):
            parsed = cast(dict[str, Any], value)
        elif "results" in raw_dict:
            parsed = raw_dict
    elif isinstance(raw_result, str):
        loaded = json.loads(raw_result)
        if isinstance(loaded, dict):
            parsed = cast(dict[str, Any], loaded)

    return parsed


def _extract_json_object(text: str) -> dict[str, Any] | None:
    """Best-effort parser for a JSON object embedded in model output."""
    stripped = text.strip()
    if not stripped:
        return None

    try:
        parsed = json.loads(stripped)
        if isinstance(parsed, dict):
            return cast(dict[str, Any], parsed)
    except json.JSONDecodeError:
        pass

    start = stripped.find("{")
    end = stripped.rfind("}")
    if start >= 0 and end > start:
        candidate = stripped[start : end + 1]
        try:
            parsed = json.loads(candidate)
            if isinstance(parsed, dict):
                return cast(dict[str, Any], parsed)
        except json.JSONDecodeError:
            return None
    return None


def _reorder_products_by_ids(
    products: list[dict[str, Any]],
    ordered_ids: list[str],
) -> list[dict[str, Any]]:
    by_id = {
        str(product.get("id")): product
        for product in products
        if isinstance(product.get("id"), str)
    }
    ranked: list[dict[str, Any]] = []
    used: set[str] = set()

    for product_id in ordered_ids:
        if product_id in used:
            continue
        product = by_id.get(product_id)
        if product is None:
            continue
        ranked.append(product)
        used.add(product_id)

    for product in products:
        product_id = product.get("id")
        if not isinstance(product_id, str) or product_id in used:
            continue
        ranked.append(product)
        used.add(product_id)

    return ranked


async def _rank_products_with_llm(
    query: str,
    products: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], str]:
    """Rank retrieved products with an LLM so every search uses model reasoning."""
    if not products:
        return products, "llm ranked 0 products"

    candidates: list[dict[str, Any]] = []
    for product in products[:8]:
        product_id = product.get("id")
        product_name = product.get("name")
        if not isinstance(product_id, str) or not isinstance(product_name, str):
            continue
        candidates.append(
            {
                "id": product_id,
                "name": product_name,
                "category": product.get("category"),
                "price": product.get("basePrice"),
            }
        )

    if not candidates:
        return products, f"llm ranked {len(products)} products"

    prompt = {
        "query": query,
        "candidates": candidates,
        "task": "Return candidate IDs ordered by semantic relevance to the query.",
        "output": {
            "ordered_ids": ["candidate_id_1", "candidate_id_2"],
            "reason": "short reason",
        },
    }

    headers = {"Content-Type": "application/json"}
    if NVIDIA_API_KEY:
        headers["Authorization"] = f"Bearer {NVIDIA_API_KEY}"

    payload = {
        "model": NIM_LLM_MODEL,
        "temperature": 0,
        "max_tokens": 220,
        "messages": [
            {
                "role": "system",
                "content": (
                    "You are an e-commerce search ranker. "
                    "Return valid JSON only with key ordered_ids as an array of candidate IDs. "
                    "Do not wrap JSON in markdown fences."
                ),
            },
            {
                "role": "user",
                "content": json.dumps(prompt, ensure_ascii=False),
            },
        ],
    }

    last_error: Exception | None = None
    for attempt in range(2):
        try:
            async with httpx.AsyncClient(timeout=45.0) as client:
                response = await client.post(
                    f"{NIM_LLM_BASE_URL}/chat/completions",
                    headers=headers,
                    json=payload,
                )
                response.raise_for_status()
                data = response.json()

            choices = data.get("choices")
            if not isinstance(choices, list) or not choices:
                raise ValueError("LLM ranker returned no choices")

            first = choices[0]
            message = first.get("message") if isinstance(first, dict) else None
            content = message.get("content") if isinstance(message, dict) else None
            if not isinstance(content, str):
                raise ValueError("LLM ranker returned invalid content")

            parsed = _extract_json_object(content)
            if not parsed:
                raise ValueError("Unable to parse ranking JSON from LLM")

            ordered_ids_raw = parsed.get("ordered_ids", [])
            ordered_ids = [
                item.strip()
                for item in ordered_ids_raw
                if isinstance(item, str) and item.strip()
            ]
            ranked = _reorder_products_by_ids(products, ordered_ids)
            return ranked, f"llm reranked {len(ranked)} products"
        except (httpx.TimeoutException, httpx.NetworkError, ValueError) as exc:
            last_error = exc
            if attempt == 0:
                logger.warning("LLM ranking retry for query '%s' due to %r", query, exc)
                continue
            raise

    if last_error is not None:
        raise last_error
    raise RuntimeError("LLM ranking failed without explicit error")


async def _fetch_product_from_merchant(product_id: str) -> dict[str, Any] | None:
    """Fetch a product from the merchant API.

    This is the single source of truth for product data.
    Returns None if the product doesn't exist in the merchant database.
    """
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(f"{MERCHANT_API_URL}/products/{product_id}")
            if response.status_code != 200:
                logger.debug(
                    f"Product {product_id} not found in merchant API: {response.status_code}"
                )
                return None
            product = response.json()
            return {
                "id": product.get("id", product_id),
                "sku": product.get("sku", ""),
                "name": product.get("name", ""),
                "basePrice": product.get("base_price", product.get("price_cents", 0)),
                "stockCount": product.get("stock_count", 0),
                "category": product.get("category", ""),
                "description": product.get("description", ""),
                "imageUrl": product.get("image_url"),
            }
    except Exception as e:
        logger.warning(f"Failed to fetch product {product_id} from merchant API: {e}")
        return None


async def call_search_agent(
    query: str,
    category: str | None,
    limit: int,
) -> dict[str, Any]:
    """Call the NAT RAG search agent to retrieve top products."""
    payload = {
        "input_message": json.dumps(
            {
                "query": query,
                "category": category,
                "limit": limit,
            }
        )
    }

    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.post(
                f"{SEARCH_AGENT_URL}/generate",
                json=payload,
            )
            response.raise_for_status()
            raw_result = response.json()
            parsed = _parse_search_agent_response(raw_result)
            raw_items = parsed.get("results")
            if not isinstance(raw_items, list):
                raw_items = parsed.get("candidates")
            items: list[dict[str, Any]] = []
            if isinstance(raw_items, list):
                for item in raw_items:
                    if not isinstance(item, dict):
                        continue
                    product_id = item.get("product_id") or item.get("id")
                    product_name = item.get("product_name") or item.get("name")
                    if not product_id or not product_name:
                        continue
                    items.append(
                        {
                            "product_id": product_id,
                            "product_name": product_name,
                            "distance": item.get("distance"),
                            "score": item.get("score"),
                            "similarity": item.get("similarity"),
                        }
                    )
            return {
                "query": parsed.get("query") or parsed.get("user_query") or query,
                "results": items,
            }
    except httpx.TimeoutException:
        return {"results": [], "error": "Search agent timeout"}
    except httpx.HTTPStatusError as e:
        return {"results": [], "error": f"Agent error: {e.response.status_code}"}
    except (httpx.ConnectError, httpx.ConnectTimeout) as e:
        return {"results": [], "error": f"Search agent unavailable: {e}"}
    except Exception as e:
        return {"results": [], "error": str(e)}


async def search_products(
    query: str,
    category: str | None = None,
    limit: int = 10,
) -> dict[str, Any]:
    """
    Search for products by query and optional category.

    Delegates search entirely to the NAT RAG search agent, then enriches
    results from the merchant API. Returns 0 results if no matching products
    exist in the database (e.g., searching for "skirts" when none exist).

    This is the entry point tool that exposes the widget URI to clients.
    The client discovers the widget location by calling this tool and reading
    the _meta.openai/outputTemplate field in the response.

    Args:
        query: Search query for products.
        category: Optional category filter.
        limit: Maximum number of results to return (default: 10, max: 50).

    Returns:
        Dictionary containing products, query info, and widget metadata.
    """
    limit = min(limit, 50)

    logger.info(f"Search request: query='{query}', category={category}, limit={limit}")

    agent_result = await call_search_agent(query=query, category=category, limit=limit)
    if agent_result.get("error"):
        logger.warning(f"Search agent error: {agent_result.get('error')}")
        return _error_search_response(
            query=query,
            category=category,
            message=f"Search agent unavailable for '{query}'.",
        )

    agent_items = agent_result.get("results", [])
    logger.info(f"Search agent returned {len(agent_items)} results")

    if SEARCH_DISTANCE_CUTOFF > 0:
        filtered_items: list[dict[str, Any]] = []
        has_distances = False
        for item in agent_items:
            distance = _extract_distance(item)
            if distance is None:
                continue
            has_distances = True
            if distance <= SEARCH_DISTANCE_CUTOFF:
                filtered_items.append(item)
        if has_distances:
            logger.info(
                "Applied distance filter (max=%s): %s -> %s",
                SEARCH_DISTANCE_CUTOFF,
                len(agent_items),
                len(filtered_items),
            )
            agent_items = filtered_items

    if SEARCH_MIN_SIMILARITY > 0:
        filtered_items: list[dict[str, Any]] = []
        has_scores = False
        for item in agent_items:
            similarity = _extract_similarity(item)
            if similarity is None:
                continue
            has_scores = True
            if similarity >= SEARCH_MIN_SIMILARITY:
                filtered_items.append(item)
        if has_scores:
            logger.info(
                f"Applied similarity filter (min={SEARCH_MIN_SIMILARITY}): {len(agent_items)} -> {len(filtered_items)}"
            )
            agent_items = filtered_items

    results: list[dict[str, Any]] = []
    for item in agent_items:
        product_id = item.get("product_id") or item.get("productId")
        if not product_id:
            logger.warning(f"Agent returned item without product_id: {item}")
            continue

        enriched = await _fetch_product_from_merchant(product_id)
        if enriched:
            results.append(enriched)
        else:
            logger.debug(
                f"Product {product_id} returned by agent not found in merchant database (skipping)"
            )

    if len(results) > limit:
        results = results[:limit]

    if not results:
        logger.info(f"No products found for query '{query}'")
        return _error_search_response(
            query=query,
            category=category,
            message=f"No products found for '{query}'.",
        )

    try:
        results, activity = await _rank_products_with_llm(query=query, products=results)
    except Exception as exc:
        logger.warning("LLM ranking failed for query '%s': %r", query, exc)
        return _error_search_response(
            query=query,
            category=category,
            message=f"LLM ranking failed for '{query}'.",
        )

    logger.info(f"Returning {len(results)} products for query '{query}'")
    return {
        "products": results,
        "query": query,
        "category": category,
        "totalResults": len(results),
        "user": DEFAULT_USER,
        "theme": "dark",
        "locale": "en-US",
        "agent_mode": "llm",
        "agent_model": NIM_LLM_MODEL,
        "nim_mode": NIM_RUN_MODE,
        "agent_activity": activity,
        "_meta": {
            "openai/outputTemplate": "ui://widget/merchant-app.html",
            "openai/toolInvocation/invoking": "Searching products...",
            "openai/toolInvocation/invoked": f"Found {len(results)} products",
            "openai/widgetAccessible": True,
        },
    }
