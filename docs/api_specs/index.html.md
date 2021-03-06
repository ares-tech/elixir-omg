---
title: OmiseGO Plasma API Reference

language_tabs: # must be one of https://git.io/vQNgJ
  - shell
  - elixir
  - javascript

toc_footers:
  - <a href='https://github.com/lord/slate'>Documentation Powered by Slate</a>

includes:
  - operator_api_specs
  - watcher_api_specs
  - watcher_websocket_specs
  - informational_api_specs
  - integration_libraries
  - errors

search: true
---

# Introduction

This is the HTTP-RPC API for the ChildChain and Watcher.

All calls use HTTP POST and pass options in the request body in JSON format.
Errors will usually return with HTTP response code 200, and the details of the error in the response body. See [Errors](#errors).
