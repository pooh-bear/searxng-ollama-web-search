# SPDX-License-Identifier: AGPL-3.0-or-later
"""Ollama web search API

.. _Ollama web search API: https://docs.ollama.com/capabilities/web-search

Configuration
=============

The engine needs an Ollama API key, either in :py:obj:`api_key` or in the
``OLLAMA_API_KEY`` environment variable of the SearXNG process::

  - name: ollama web
    engine: ollama_web
    api_key: 'YOUR-OLLAMA-API-KEY'  # or set env OLLAMA_API_KEY
    results_per_page: 10            # optional, the API allows 1..10

Ollama's web search is a cloud service (Ollama Pro/Max/Team, or pay-as-you-go
credits) and supports neither paging, nor time ranges, nor safe-search, hence
the API is queried once and returns at most 10 results per request.
"""

import os
import json
import typing as t

from searx.exceptions import SearxEngineAPIException
from searx.result_types import EngineResults

if t.TYPE_CHECKING:
    from searx.extended_types import SXNG_Response

about = {
    "website": "https://ollama.com",
    "wikidata_id": "Q124636097",
    "official_api_documentation": "https://docs.ollama.com/capabilities/web-search",
    "use_official_api": True,
    "require_api_key": True,
    "results": "JSON",
}

categories = ["general", "web"]
paging = False
safesearch = False
time_range_support = False
language_support = False

base_url = "https://ollama.com/api/web_search"
"""Endpoint of the Ollama web search API."""

api_key: str = ""
"""API key of the Ollama account, falls back to the ``OLLAMA_API_KEY`` env variable."""

results_per_page: int = 10
"""Number of results to request; the API accepts 1..10 (its default is 5)."""


def init(_):
    global api_key  # pylint: disable=global-statement
    if not api_key:
        api_key = os.environ.get("OLLAMA_API_KEY", "")
    if not api_key:
        raise SearxEngineAPIException("No API key provided")


def request(query: str, params) -> None:
    params["method"] = "POST"
    params["url"] = base_url
    params["headers"]["Authorization"] = f"Bearer {api_key}"
    params["headers"]["Content-Type"] = "application/json"
    params["data"] = json.dumps(
        {
            "query": query,
            "max_results": max(1, min(10, results_per_page)),
        }
    )


def response(resp: "SXNG_Response") -> EngineResults:
    res = EngineResults()

    for result in resp.json().get("results") or []:
        res.add(
            res.types.MainResult(
                title=result.get("title") or "",
                url=result.get("url") or "",
                content=result.get("content") or "",
            )
        )

    return res
