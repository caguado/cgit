-----------------------------------------------------------------------------
-- Gerrit authorization handler for cgit
--
-- Uses the REST API endpoint to perform authorization requests for
-- repositories and refnames visible to the specified user. It assumes
-- is being run by a proxy agent via exec/X-Gerrit-RunAs.
--
-- This handler depends on the following Lua libraries:
-- cURL: binding for libcurl for Keberos handling
-- cjson: deserializer for the JSON output of the REST API endpoint
--
-- Based on the Browser Class for easy Web Automation with Lua-cURL
-- from: Kai Uwe Jesussek
-----------------------------------------------------------------------------
package.cpath = package.cpath .. ";/usr/lib64/lua/5.1/?.so"
package.path = package.path .. ";/usr/share/lua/5.1/?.lua"

curl = require("lcurl")
string = require("string")
table = require("table")
json = require("cjson")
base = _G

-----------------------------------------------------------------------------
-- Global parameters and constants
-----------------------------------------------------------------------------
-- Basic constants to query an authentication endpoint
VERBOSE = 0
if os.getenv("CGIT_AUTH_VERBOSE") then
	VERBOSE = 1
end
USERAGENT = "cgit/0.11.2"
REST_PROJECT_ENDPOINT = "projects"
REST_BRANCH_ENDPOINT = "branches"
REST_BRANCH_NAME = "ref"
REST_TAG_ENDPOINT = "tags"
REST_TAG_NAME = "ref"
REST_COMMIT_ENDPOINT = "commits"
REST_COMMIT_NAME = "commit"

-- Parameters of the local authentication instance
REST_BASE_ENDPOINT = assert (os.getenv("CGIT_AUTH_ENDPOINT"), "Missing envar CGIT_AUTH_ENDPOINT")
REST_RUNAS_HEADER = assert (os.getenv("CGIT_AUTH_PROXY_HEADER"), "Missing envar CGIT_AUTH_PROXY_HEADER")
REST_PROXY_USER = assert (os.getenv("CGIT_AUTH_PROXY_USER"), "Missing envar CGIT_AUTH_PROXY_USER")

-----------------------------------------------------------------------------
-- Helper functions
-----------------------------------------------------------------------------
-- data dumper borrowed from stackoverflow:
-- http://stackoverflow.com/questions/6075262/lua-table-tostringtablename-and-table-fromstringstringtable-functions
function serialize_table(val, name, skipnewlines, depth)
	skipnewlines = skipnewlines or false
	depth = depth or 0

	local tmp = string.rep(" ", depth)

	if name then tmp = tmp .. name .. " = " end

	if type(val) == "table" then
		tmp = tmp .. "{" .. (not skipnewlines and "\n" or "")

		for k, v in pairs(val) do
			tmp =  tmp .. serialize_table(v, k, skipnewlines, depth + 1) .. "," .. (not skipnewlines and "\n" or "")
		end

		tmp = tmp .. string.rep(" ", depth) .. "}"
	elseif type(val) == "number" then
		tmp = tmp .. tostring(val)
	elseif type(val) == "string" then
		tmp = tmp .. string.format("%q", val)
	elseif type(val) == "boolean" then
		tmp = tmp .. (val and "true" or "false")
	else
		tmp = tmp .. "\"[inserializeable datatype:" .. type(val) .. "]\""
	end

	return tmp
end

--this function joins 2 urls (absolute or relative)
function url_join(_base, _url)
	assert(type(_url) == "string")

	if _base == nil or _base == "" then
		return _url
	end

	assert(type(_base) == "string")
	local base = url_split(_base)
	local url = url_split(_url)


	local protocol = base.protocol
	local host = base.host

	local path = ""
	local port = ""

	if url.protocol ~= nil then
		protocol = url.protocol
		if url.path ~= nil then
			path = url.path
		end
		if url.port ~= nil and url.port ~= "" then
			port = url.port
		end
		if url.host ~= nil then
			host = url.host
		end
	else
		if _url:sub(1,2) == "//" then
			--set host and path
			host, port, path = _url:match("^//([^;/%?]+)(:?%d*)(/?.*)")
			if path == nil then
				path = ""
			end
		elseif _url:sub(1,1) == "/" then
			port = base.port
			--replace path
			path = _url
		else
			--combine paths :(
			path = base.path:match("^(.*)/[^/]*")
			port = base.port
			if path ~= nil then
				path = path .. "/" .. _url
			else
				path = _url
			end
		end

	end
	local ret = protocol .. "://" .. host .. port .. path
	return ret
end

--this function splits an url into its parts
function url_split(_url)
	--print(_url)
	local ret = {}
	--test ipv6
	ret.protocol, ret.host, ret.port, ret.path = _url:match("^(https?)://(%[[0-9a-fA-F:]+%])(:?%d*)(.*)$")

	if ret.host == nil then
		--fall back to ipv4
		ret.protocol, ret.host, ret.port, ret.path = _url:match("^(https?)://([^:/]+)(:?%d*)(.*)$")
	end
	return ret
end


-----------------------------------------------------------------------------
-- Encodes a string into its escaped hexadecimal representation
-- Input
--   s: binary string to be encoded
-- Returns
--   escaped representation of string binary
-- taken from Lua Socket and added underscore to ignore (MIT-License)
-----------------------------------------------------------------------------
function escape(s)
	return string.gsub(s, "([^A-Za-z0-9_])", function(c)
		return string.format("%%%02x", string.byte(c))
		end)
end

-----------------------------------------------------------------------------
-- Encodes a string into its escaped hexadecimal representation
-- Input
--   s: binary string to be encoded
-- Returns
--   escaped representation of string binary
-- taken from Lua Socket
-----------------------------------------------------------------------------
function unescape(s)
	return string.gsub(s, "%%(%x%x)", function(hex)
		return string.char(base.tonumber(hex, 16))
		end)
end

-- Covert a table of tables into a set for a given
-- key in each nested table.
-- If a key is not passed, use the key of the parent
-- table as key.
-- http://www.lua.org/pil/13.1.html
function make_set (list, key)
	local set = {}
	for k, v in pairs(list) do
		if key ~= nil and v[key] ~= nil then
			set[v[key]] = true
		else
			set[k] = true
		end
	end
	return set
end

--
-- Utility functions based on keplerproject/wsapi.
--
function url_decode(str)
	if not str then
		return ""
	end
	str = string.gsub(str, "+", " ")
	str = string.gsub(str, "%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
	str = string.gsub(str, "\r\n", "\n")
	return str
end

function url_encode(str)
	if not str then
		return ""
	end
	str = string.gsub(str, "\n", "\r\n")
	str = string.gsub(str, "([^%w ])", function(c) return string.format("%%%02X", string.byte(c)) end)
	str = string.gsub(str, " ", "+")
	return str
end

function parse_querystring(qs)
	local tab = {}
	for key, val in string.gmatch(qs, "([^&=]+)=([^&=]*)&?") do
		tab[url_decode(key)] = url_decode(val)
	end
	return tab
end


--function helper for headers
--taken from luasocket page (MIT-License)
local function save_headers_callback(t)
        return function(h)
                --stores the received data in the table t
                --prepare header data
                name, value = h:match("(.-): (.+)")
                if name and value then
                        t.headers[name] = value:gsub("[\n\r]", "")
                else
                        code, codemessage = string.match(h, "^HTTP/.* (%d+) (.+)$")
                        if code and codemessage then
                                t.code = tonumber(code)
                                t.codemessage = codemessage:gsub("[\n\r]", "")
                        end
                end
        end
end


--function helper for result
--taken from luasocket page (MIT-License)
local function save_body_callback(t)
        return function(b)
                table.insert(t, b)
        end
end

-----------------------------------------------------------------------------
-- Browser functions
-----------------------------------------------------------------------------
browser = {}

function browser:new(_share)
	if _share == nil then
                _share = curl.share()
                          :setopt_share(curl.LOCK_DATA_COOKIE)
                          :setopt_share(curl.LOCK_DATA_DNS)
        end
        local object = {
                url = nil,
                share = _share,
                headers = {}
        }
        setmetatable(object, {__index = browser})
        return object
end

--this function sets the url 
function browser:setUrl(url)
	--appends a leading / to url if needed
	if self.url and self.url:match("^(https?://[^/]+)$") then
		self.url = self.url .. "/"
	end
	self.url = url_join(self.url or "", url)
end

function browser:setHeader(_header, _value)
        if _header ~= nil and _value ~= nil then
                header = _header .. ": " .. _value
                table.insert(self.headers, header)
        end
end

--this function prepares a request
function browser:prepare()
	local req = curl.easy()
	req:setopt_share(self.share)
	req:setopt_url(self.url)
	req:setopt_useragent(USERAGENT)

        req:setopt_httpheader(self.headers)
        req:setopt_cookiefile("")
        req:setopt_followlocation(1)
        req:setopt_username("")
        req:setopt_password("")
        req:setopt_httpauth(curl.AUTH_GSSNEGOTIATE)
        req:setopt_verbose(VERBOSE)

	return req
end

--opens a webpage only the first parameter is required
function browser:open(url, redirect)
	local redirect = redirect or true
	local ret = {}
	response_body = {}
	ret.headers = {}

	self:setUrl(url)
	local req = self:prepare()
	req:setopt_headerfunction(save_headers_callback(ret))
	req:setopt_writefunction(save_body_callback(response_body))
	req:perform()
	req:close()

	if VERBOSE ~= 0 then io.stderr:write(serialize_table(ret.headers)) end
	if VERBOSE ~= 0 then io.stderr:write(serialize_table(response_body)) end
	ret.body = table.concat(response_body)

	if redirect and ret.headers and (ret.headers.Location or ret.headers.location) and (ret.code == 301 or ret.code == 302) then
		return self:open(url_join(self.url, ret.headers.Location or ret.headers.location), redirect)
	end
	return ret

end

-----------------------------------------------------------------------------
-- Authorization functions
-----------------------------------------------------------------------------
authpdp = {}
-- Create a authpdp handler
-- Requires:
--   AuthZ URL
--   User with super cow powers
--   Target user to query
function authpdp:new(_url, _superuser, _user)
        local object = {
		url = _url,
		superuser = _superuser,
		user = _user
	}
        setmetatable(object, {__index = authpdp})
        return object
end

-- Get list of projects with at least one branch visible to the user
function authpdp:getProjectNames()
	local query = REST_PROJECT_ENDPOINT .. "/"
	return make_set(self:runAs(self.user, query))
end

-- Get list of branches visible to user in a project
-- Requires:
--   Authz target project
function authpdp:getBranchNames(_project)
	if _project ~= nil then
		local query = REST_PROJECT_ENDPOINT  .. "/" ..
				escape(_project)     .. "/" ..
				REST_BRANCH_ENDPOINT .. "/"
		return make_set(self:runAs(self.user, query), REST_BRANCH_NAME)
	end
	return {}
end

-- Get list of tags visible to user in a project
-- Requires:
--   Authz target project
function authpdp:getTagNames(_project)
	if _project ~= nil then
		local query = REST_PROJECT_ENDPOINT .. "/" ..
				escape(_project)    .. "/" ..
				REST_TAG_ENDPOINT   .. "/"
		return make_set(self:runAs(self.user, query), REST_TAG_NAME)
	end
	return {}
end

-- Get list of refs visible to user in a project
-- NOT IMPLEMENTED
-- Requires:
--   Authz target project
function authpdp:getRefNames(_project)
	return {}
end

-- Query the commit info for a give project and sha1
-- Alternatively a simple HEAD request may suffice to
-- accomplish the same authorization goal
-- Requires:
--   Authz target project
--   Authz target sha1
function authpdp:getCommit(_project, _sha1)
	if _project ~= nil then
		local query = REST_PROJECT_ENDPOINT  .. "/" ..
				escape(_project)     .. "/" ..
				REST_COMMIT_ENDPOINT .. "/" ..
				_sha1
		commit = self:runAs(self.user, query)
		if commit[REST_COMMIT_NAME] == _sha1 then
			return { [_sha1] = true; }
		end
	end
	return {}
end

-- Run functional query for the target user
-- Requires:
--   Authz target user
--   Function to query authpdp
function authpdp:runAs(_user, _query)
	local bhandler = browser:new()
	bhandler:setHeader("Accept", "application/json")
	bhandler:setHeader("Cache-Control", "no-cache")
	bhandler:setHeader(REST_RUNAS_HEADER, _user)
	local response = bhandler:open(self.url .. _query)
	if response.code == 200 then
		-- Remove the )]}' inserted by authpdp for xss protection
		local jsonbody = string.sub(response.body, 6)
		return json.decode(jsonbody)
	end
	return {}
end

-----------------------------------------------------------------------------
-- Cgit functions
-----------------------------------------------------------------------------
local function generate_functor(key, map)
	return function(self, v, ...)
		local obj = self
		if key ~= "" then obj = self[key] end
		v = assert(map[v], "Unsupported value " .. tostring(v))
		return v(obj, ...)
	end
end

cgit = {}
-- Create a authpdp handler
-- Requires:
--   Authz object handler
function cgit:new(_authpdp)
	local _ops_functor = generate_functor("",{
		["authenticate-post"  ] = self.authenticate_post;
		["authenticate-cookie"] = self.authenticate_cookie;
		["authorize-repo"     ] = self.authorize_repo;
		["authorize-ref"      ] = self.authorize_ref;
		["authorize-commit"   ] = self.authorize_commit;
		["body"               ] = self.body;
	})

	local _ref_functor = generate_functor("authpdp", {
		["heads"  ] = _authpdp.getBranchNames;
		["tags"   ] = _authpdp.getTagNames;
		["changes"] = _authpdp.getRefNames;
		["HEAD"   ] = _authpdp.getBranchNames;
	})

        local object = {
		authpdp = _authpdp,
		valid_ops = _ops_functor,
		authz_ref = _ref_functor,
		operation = "",
		request = {},
		authpdpop = {},
	}
        setmetatable(object, {__index = cgit})
        return object
end

function cgit:set_operation(_operation)
	self.operation = _operation
end

function cgit:set_request(_request)
	self.request = _request
end

function cgit:authenticate_post()
	html("\n")
        return 0
end

function cgit:authenticate_cookie()
	return 1
end

-- Query authpdp for access to a given repository.
-- To minimize latency and QPS, the query will be
-- for all the repositories available to the user
-- and the authorization matching happens here.
function cgit:authorize_repo()
	local operation = "authorize_repo"
	if self.authpdpop[operation] == nil then
		self.authpdpop[operation] = self.authpdp:getProjectNames()
	end
	if self.authpdpop[operation] ~= nil and 
		self.authpdpop[operation][self.request["repo"]] then
		if VERBOSE ~= 0 then
			 io.stderr:write("Authorizing repo " .. self.request["repo"])
		end
		return 1
	else
		if VERBOSE ~= 0 then
			io.stderr:write("NOT authorizing repo " .. self.request["repo"])
		end
		return 0
	end
end

-- Query authpdp for all the refnames available
-- to a user in a given repository.
-- To minimize latency and QPS, the query will be
-- for all the refnames available to the user
-- and the authorization matching happens here.
function cgit:authorize_ref()
	-- a request["head"] will contain refs/* or HEAD
	local reftype = self.request["head"]:match("^refs/([^/]*)/.*$") or self.request["head"]
	local operation = "authorize_ref_" .. reftype
	if self.authpdpop[operation] == nil then
		auth_ok, auth_out = pcall(self.authz_ref, self, reftype, self.request["repo"])
		if auth_ok then
			self.authpdpop[operation] = auth_out
		else
			if VERBOSE ~= 0 then
				io.stderr:write("ERROR with " .. reftype .. ": " .. auth_out)
			end
		end
	end
	if reftype == "changes" then
		if VERBOSE ~= 0 then
			io.stderr:write("Authorizing changes automatically " .. self.request["head"])
		end
		return 1
	end
	if self.authpdpop[operation] ~= nil and
                self.authpdpop[operation][self.request["head"]] then
		if VERBOSE ~= 0 then
			io.stderr:write("Authorizing ref " .. self.request["head"])
		end
		return 1
	else
		if VERBOSE ~= 0 then
			io.stderr:write("NOT authorizing ref " .. self.request["head"])
		end
		return 0
	end
end

-- Query authpdp for a commit to be displayed where for
-- compatibility the authorization still happens here.
function cgit:authorize_commit()
	-- a request["head"] will contain a commit SHA1
	local operation = "authorize_commit"
	if self.authpdpop[operation] == nil then
		self.authpdpop[operation] = self.authpdp:getCommit(self.request["repo"], self.request["head"])
	end
	if self.authpdpop[operation] ~= nil and
		self.authpdpop[operation][self.request["head"]] then
		if VERBOSE ~= 0 then
			io.stderr:write("Authorizing commit " .. self.request["head"])
		end
		return 1
	else
		if VERBOSE ~= 0 then
			io.stderr:write("NOT authorizing commit " .. self.request["head"])
		end
		return 0
	end
end

function cgit:body()
	html("\n")
	return 0
end

function cgit:do_operation()
	return self:valid_ops(self.operation)
end

-----------------------------------------------------------------------------
-- Interface to Lua cgit
-----------------------------------------------------------------------------
function filter_open(...)
	local operation = select(1, ...)

	local request = {}
	request["cookie"]  = select(2, ...)
	request["method"]  = select(3, ...)
	request["query"]   = select(4, ...)
	request["referer"] = select(5, ...)
	request["path"]    = select(6, ...)
	request["host"]    = select(7, ...)
	request["https"]   = select(8, ...)
	request["user"]    = select(9, ...)
	request["repo"]    = select(10, ...)
	request["head"]    = select(11, ...)
	request["page"]    = select(12, ...)
	request["url"]     = select(13, ...)
	request["login"]   = select(14, ...)

	-- Initialize authpdp and cgit handlers as singletons in global variables
	if authpdphandler == nil then
		authpdphandler = authpdp:new(REST_BASE_ENDPOINT, REST_PROXY_USER, request["user"])
	end
	if cgithandler == nil then
		cgithandler = cgit:new(authpdphandler)
	end
	cgithandler:set_operation(operation)
	cgithandler:set_request(request)
end

function filter_close()
	return cgithandler:do_operation()
end

function filter_write(str)
	post = parse_querystring(str)
end

