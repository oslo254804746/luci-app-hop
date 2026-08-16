// Copyright 2026 Hop maintainers
// Licensed to the public under the MIT License.

'use strict';

import { readfile } from 'fs';
import * as socket from 'socket';

const PANEL_INDEX = '/usr/share/hop/panel/index.html';
const API_ROUTE = '/admin/services/hop/api/v1';
const API_PREFIX = '/api/v1';
const BLOCK_SIZE = 8192;
const MAX_HEADER_SIZE = 16384;
const MAX_REQUEST_BODY = 1024 * 100;
const MAX_RESPONSE_BODY = 1024 * 2048;
const POLL_TIMEOUT = 5000;

function json_error(status, reason, code, message) {
	http.status(status, reason);
	http.header('Cache-Control', 'no-store');
	http.header('X-Content-Type-Options', 'nosniff');
	http.prepare_content('application/json; charset=UTF-8');
	http.write_json({ code, message });
}

function panel_document() {
	let page = readfile(PANEL_INDEX);

	if (!page)
		return null;

	let api_url = dispatcher.build_url('admin', 'services', 'hop', 'api', 'v1');
	let service_url = dispatcher.build_url('admin', 'services', 'hop', 'settings');

	page = replace(page,
		/<meta name="hop-control-api-base" content="[^"]*"\s*\/?>/,
		`<meta name="hop-control-api-base" content="${api_url}" />`);
	page = replace(page,
		/<meta name="hop-service-url" content="[^"]*"\s*\/?>/,
		`<meta name="hop-service-url" content="${service_url}" />`);
	page = replace(page,
		/<meta name="hop-deployment" content="[^"]*"\s*\/?>/,
		'<meta name="hop-deployment" content="openwrt" />');

	return page;
}

function api_suffix() {
	let path = http.getenv('PATH_INFO') ?? '';

	if (substr(path, 0, length(API_ROUTE)) != API_ROUTE)
		return null;

	let suffix = substr(path, length(API_ROUTE));
	return length(suffix) ? suffix : '/';
}

function allowed_request(method, path) {
	if (method == 'GET') {
		return !!match(path, /^\/(status|assets|credentials|access-keys|sessions|known-hosts)$/) ||
			path == '/catalog/revision';
	}

	if (method == 'POST') {
		return !!match(path, /^\/(assets|credentials|access-keys)$/) ||
			!!match(path, /^\/sessions\/[^/]+\/terminate$/) ||
			!!match(path, /^\/config\/(validate|diff|apply)$/);
	}

	if (method == 'PUT') {
		return !!match(path, /^\/(assets|credentials)\/[^/]+$/) ||
			!!match(path, /^\/access-keys\/[^/]+\/(enabled|access)$/);
	}

	if (method == 'DELETE')
		return path == '/known-hosts' ||
			!!match(path, /^\/(assets|credentials|access-keys)\/[^/]+$/);

	return false;
}

function send_all(sock, value) {
	let offset = 0;

	while (offset < length(value)) {
		let sent = sock.send(substr(value, offset));

		if (!sent || sent < 0)
			return false;

		offset += sent;
	}

	return true;
}

function recv_ready(sock) {
	let ready = socket.poll(POLL_TIMEOUT, [ sock, socket.POLLIN ]);

	if (!ready || !length(ready))
		return null;

	let chunk = sock.recv(BLOCK_SIZE);
	return chunk && length(chunk) ? chunk : null;
}

function read_headers(sock) {
	let buffer = '';
	let boundary = -1;

	while ((boundary = index(buffer, '\r\n\r\n')) < 0) {
		if (length(buffer) >= MAX_HEADER_SIZE)
			return null;

		let chunk = recv_ready(sock);
		if (chunk == null)
			return null;

		buffer += chunk;
	}

	return {
		head: substr(buffer, 0, boundary),
		body: substr(buffer, boundary + 4)
	};
}

function response_headers(raw) {
	let headers = {};

	for (let line in split(raw, /\r\n/)) {
		let pair = match(line, /^([^:]+):\s*(.*)$/);
		if (pair && length(pair) == 3)
			headers[lc(pair[1])] = pair[2];
	}

	return headers;
}

function append_body(chunks, chunk, size) {
	if (chunk == null)
		return size;

	let next_size = size + length(chunk);
	if (next_size > MAX_RESPONSE_BODY)
		return null;

	push(chunks, chunk);
	return next_size;
}

function read_chunked_body(sock, initial) {
	let buffer = initial ?? '';
	let chunks = [];
	let size = 0;

	while (true) {
		let line_end;
		while ((line_end = index(buffer, '\r\n')) < 0) {
			let data = recv_ready(sock);
			if (data == null)
				return null;
			buffer += data;
		}

		let size_line = substr(buffer, 0, line_end);
		let size_match = match(size_line, /^([0-9a-fA-F]+)(;.*)?$/);
		if (!size_match)
			return null;

		let chunk_size = int(size_match[1], 16);
		buffer = substr(buffer, line_end + 2);

		if (chunk_size == 0)
			return join('', chunks);

		while (length(buffer) < chunk_size + 2) {
			let data = recv_ready(sock);
			if (data == null)
				return null;
			buffer += data;
		}

		if (substr(buffer, chunk_size, 2) != '\r\n')
			return null;

		size = append_body(chunks, substr(buffer, 0, chunk_size), size);
		if (size == null)
			return null;

		buffer = substr(buffer, chunk_size + 2);
	}
}

function read_sized_body(sock, initial, content_length) {
	if (content_length < 0 || content_length > MAX_RESPONSE_BODY)
		return null;

	let body = substr(initial ?? '', 0, content_length);

	while (length(body) < content_length) {
		let data = recv_ready(sock);
		if (data == null)
			return null;

		body += substr(data, 0, content_length - length(body));
	}

	return body;
}

function read_close_body(sock, initial) {
	let chunks = [];
	let size = append_body(chunks, initial ?? '', 0);

	if (size == null)
		return null;

	while (true) {
		let data = recv_ready(sock);
		if (data == null)
			break;

		size = append_body(chunks, data, size);
		if (size == null)
			return null;
	}

	return join('', chunks);
}

function proxy_request(method, path, authorization, body) {
	let addresses = socket.addrinfo('127.0.0.1', 8083, { protocol: socket.IPPROTO_TCP });
	let destination = addresses?.[0]?.addr ? socket.sockaddr(addresses[0].addr) : null;
	let sock = destination ? socket.create(destination.family, socket.SOCK_STREAM) : null;

	if (!sock)
		return null;

	if (!sock.connect(destination)) {
		sock.close();
		return null;
	}

	let request = [
		`${method} ${API_PREFIX}${path} HTTP/1.1`,
		'Host: 127.0.0.1:8083',
		'Accept: application/json',
		`Authorization: ${authorization}`,
		'User-Agent: luci-app-hop/0.2.4',
		'Connection: close'
	];

	if (body != null && length(body)) {
		push(request, 'Content-Type: application/json');
		push(request, `Content-Length: ${length(body)}`);
	}

	push(request, '', '');

	if (!send_all(sock, join('\r\n', request)) ||
		(body != null && length(body) && !send_all(sock, body))) {
		sock.close();
		return null;
	}

	let response = read_headers(sock);
	if (!response) {
		sock.close();
		return null;
	}

	let status_line = split(response.head, /\r\n/)[0] ?? '';
	let status_match = match(status_line, /^HTTP\/[0-9.]+\s+([0-9]{3})\s*(.*)$/);
	let headers = response_headers(response.head);
	let response_body;

	if (index(lc(headers['transfer-encoding'] ?? ''), 'chunked') >= 0)
		response_body = read_chunked_body(sock, response.body);
	else if (headers['content-length'] != null)
		response_body = read_sized_body(sock, response.body, int(headers['content-length']));
	else
		response_body = read_close_body(sock, response.body);

	sock.close();

	if (!status_match || response_body == null)
		return null;

	return {
		status: int(status_match[1]),
		reason: status_match[2] || 'Hop API response',
		body: response_body
	};
}

return {
	action_panel: function() {
		let page = panel_document();

		if (!page) {
			http.status(503, 'Panel unavailable');
			http.prepare_content('text/plain; charset=UTF-8');
			http.write('Hop panel assets are not installed.');
			return;
		}

		http.header('Cache-Control', 'no-store');
		http.header('Content-Security-Policy', "default-src 'self'; base-uri 'self'; connect-src 'self' http: https:; font-src 'self'; form-action 'self'; frame-ancestors 'none'; img-src 'self' data:; object-src 'none'; script-src 'self'; style-src 'self'");
		http.header('Referrer-Policy', 'no-referrer');
		http.header('X-Content-Type-Options', 'nosniff');
		http.header('X-Frame-Options', 'DENY');
		http.prepare_content('text/html; charset=UTF-8');
		http.write(page);
	},

	action_api: function(env) {
		let method = uc(http.getenv('REQUEST_METHOD') ?? '');
		let path = api_suffix();
		let query = http.getenv('QUERY_STRING') ?? '';
		let authorization = http.getenv('HTTP_AUTHORIZATION') ?? '';
		let content_length = int(http.getenv('CONTENT_LENGTH') ?? '0');

		if (path == null || length(path) > 2048 ||
			match(path, /[\r\n\\?#]/) || match(path, /(^|\/)\.\.?($|\/)/)) {
			json_error(404, 'Not Found', 'not_found', 'Unknown Hop Control API path');
			return;
		}

		if (length(query) || !allowed_request(method, path)) {
			json_error(404, 'Not Found', 'not_found', 'Unknown Hop Control API operation');
			return;
		}

		if (method != 'GET' && env?.dispatched?.readonly) {
			json_error(403, 'Forbidden', 'read_only', 'This LuCI session has read-only Hop access');
			return;
		}

		if (length(authorization) < 8 || length(authorization) > 8192 ||
			substr(authorization, 0, 7) != 'Bearer ' || match(authorization, /[\r\n]/)) {
			json_error(401, 'Unauthorized', 'unauthorized', 'A Bearer management token is required');
			return;
		}

		if (content_length < 0 || content_length > MAX_REQUEST_BODY) {
			json_error(413, 'Content Too Large', 'request_too_large', 'The Hop API request body is too large');
			return;
		}

		let body = (method == 'POST' || method == 'PUT' || method == 'DELETE') ? http.content() : null;
		if (body != null && length(body) > MAX_REQUEST_BODY) {
			json_error(413, 'Content Too Large', 'request_too_large', 'The Hop API request body is too large');
			return;
		}

		let response = proxy_request(method, path, authorization, body);
		if (!response) {
			json_error(502, 'Bad Gateway', 'upstream_unavailable', 'Hop Control API is unavailable');
			return;
		}

		http.status(response.status, response.reason);
		http.header('Cache-Control', 'no-store');
		http.header('X-Content-Type-Options', 'nosniff');
		http.prepare_content('application/json; charset=UTF-8');
		http.write(response.body);
	}
};
