local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local utils = {}

local pystring = require(script.Parent.pystring)

function utils:Color1to255(v: number): number
	return math.floor(v*255)
end

function utils:ColorToString(color3: Color3): string
	local r, g, b = color3.R, color3.G, color3.B
	local r255, g255, b255 = utils:Color1to255(r), utils:Color1to255(g), utils:Color1to255(b)
	local rstr, gstr, bstr = tostring(r255), tostring(g255), tostring(b255)
	local c3 = {rstr, gstr, bstr}
	local str = table.concat(c3, ",", 1, 3)
	--print(str)
	return str
end

local TAG_START = "<[^>]-"
local TAG_END = "[^>]->"
local BR_PATTERN = "^<%s*[bB][rR]%s*/?%s*>"
local RICH_TEXT_PATTERN = "<[^>]->"
local HASHTAGS_ONLY_PATTERN = "^#+$"
local SIZE_PATTERN = "size%s*=%s*[\'\"]%d+[\'\"]"
local SIZE_TAG_PATTERN = TAG_START..SIZE_PATTERN..TAG_END
local FACE_PATTERN = "face%s*=%s*[\'\"]%.-[\'\"]"
local FACE_TAG_PATTERN = TAG_START..FACE_PATTERN..TAG_END
local FAMILY_PATTERN = "family%s*=%s*[\'\"]%.-[\'\"]"
local FAMILY_TAG_PATTERN = TAG_START..FAMILY_PATTERN..TAG_END
local COMMENT_PATTERN = "<!%-%-.-%-%->"
utils.BR_PATTERN = BR_PATTERN
utils.RICH_TEXT_PATTERN = RICH_TEXT_PATTERN
utils.HASHTAGS_ONLY_PATTERN = HASHTAGS_ONLY_PATTERN
utils.SIZE_PATTERN = SIZE_PATTERN
utils.SIZE_TAG_PATTERN = SIZE_TAG_PATTERN
utils.FACE_PATTERN = FACE_PATTERN
utils.FAMILY_PATTERN = FAMILY_PATTERN
utils.FACE_TAG_PATTERN = FACE_TAG_PATTERN
utils.FAMILY_TAG_PATTERN = FAMILY_TAG_PATTERN
utils.TAG_START = TAG_START
utils.TAG_END = TAG_END
utils.COMMENT_PATTERN = COMMENT_PATTERN

function utils:ToAttributeKey(str: string)
	-- Remove anything not alphanumeric or underscore
	str = string.gsub(str, "[^%w_]", "")
	return str
end

-- helper to repeatedly apply a tag transform until no more matches
local function applyTagTransform(str, openTag, closeTag, transformFn)
	local pattern = openTag .. "(.-)" .. closeTag
	while true do
		local changed = false
		str, changed = str:gsub(pattern, function(inner)
			return transformFn(inner)
		end)
		if changed == 0 then
			break
		end
	end
	return str
end

function utils:NormalizeText(str: string): string
	-- strip comments
	local i, j = str:find(COMMENT_PATTERN)
	if i and j then
		str = str:gsub(COMMENT_PATTERN, "")
	end

	-- normalize <br/> and tabs
	--str = str:gsub("<br/>", "\n")
	--str = str:gsub("\t", "    ")

	-- casing transforms (baked into text)
	-- <uppercase>...</uppercase> and <uc>...</uc>
	str = applyTagTransform(str, "<uppercase>", "</uppercase>", string.upper)
	str = applyTagTransform(str, "<uc>", "</uc>", string.upper)

	---- <smallcaps>...</smallcaps> and <sc>...</sc>
	---- for now: treat as uppercase; visual "smallness" is handled by font/size if you ever want it
	--str = applyTagTransform(str, "<smallcaps>", "</smallcaps>", string.upper)
	--str = applyTagTransform(str, "<sc>", "</sc>", string.upper)

	return str
end

function utils:RemoveRichText(str: string): string
	return (utils:NormalizeText(str):gsub(RICH_TEXT_PATTERN, ""))
end

function utils:HasRichText(str: string): boolean
	return str:find(RICH_TEXT_PATTERN) ~= nil
end

function utils:IsOnlyHashtags(str: string): boolean
	return str:match(HASHTAGS_ONLY_PATTERN) ~= nil
end

function utils:ExceedsLimit(str: string, limit: number): boolean
	return utf8.len(str) > limit
end

function utils:ExtractRows(text: string, visible_graphemes_only: boolean?): {string}
	if visible_graphemes_only == true then
		text = utils:RemoveRichText(text)
	else
		text = utils:NormalizeText(text)
	end

	local rows = {""}
	local rowIndex = 1

	local i = 1
	local n = utf8.len(text)

	while i <= n do
		local ch = text:sub(i, i)
		if ch == "\n" then
			-- new visible row
			rowIndex += 1
			rows[rowIndex] = ""
			i += 1
		else
			-- visible character
			rows[rowIndex] = rows[rowIndex] .. ch
			i += 1
		end
	end

	return rows
end

function utils:FindLongestRow(rows: {string}): string
	-- find longest visible row
	local longestRow: string = ""
	for _, row: string in ipairs(rows) do
		if utf8.len(row) > utf8.len(longestRow) then
			longestRow = row
		end
	end
	return longestRow
end

function utils:ComputeTilesPerRow(text: string)
	local rows = utils:ExtractRows(text, true)

	-- find longest visible row
	local longestRow: string = utils:FindLongestRow(rows)
	local maxLen: number = utf8.len(longestRow)

	-- compute tiles per row
	return math.ceil(maxLen / utils.COLS_PER_NOTE)
end

function utils:fromHex(hex: string)
	hex = hex:upper()

	local digits = "0123456789ABCDEF"
	local value = 0

	for i = 1, #hex do
		local c = hex:sub(i, i)
		local d = digits:find(c, 1, true)

		if not d then
			error("Invalid hex digit: " .. c)
		end

		d -= 1 -- because find() returns 1–16, but hex digits are 0–15

		value = value * 16 + d
	end

	return value
end

function utils:toHex(n: number)
	if n == 0 then
		return "0"
	end

	local hex = ""
	local digits = "0123456789ABCDEF"

	while n > 0 do
		local d = n % 16
		n = (n - d) / 16
		hex = digits:sub(d + 1, d + 1) .. hex
	end

	return hex
end

---------------------------------------------------------------------
-- Tokenizer
---------------------------------------------------------------------
local function tokenizeRichText(str: string)
	local tokens = {}
	local i = 1
	local len = utf8.len(str)
	while i <= len do
		local c = str:sub(i, i)

		if c == "<" then
			local close = str:find(">", i)
			if close then
				table.insert(tokens, str:sub(i, close))
				i = close + 1
			else
				table.insert(tokens, c)
				i += 1
			end

		elseif c == "\n" then
			table.insert(tokens, "\n")
			i += 1

		else
			table.insert(tokens, c)
			i += 1
		end
	end
	return tokens
end

local function isTag(token: string)
	return token:sub(1, 1) == "<" and token:sub(-1) == ">"
end

local function isClosingTag(tag: string)
	return tag:sub(1, 2) == "</"
end

local function getTagName(tag: string)
	return tag:match("^</?([%w]+)")
end

---------------------------------------------------------------------
-- Ensure tile exists (band-based newline backfill, deterministic)
---------------------------------------------------------------------
local function ensureTile(tiles, ty: number, tx: number, rowsCompletedPerBand)
	if not tiles[ty] then
		tiles[ty] = {}
	end

	if not tiles[ty][tx] then
		local completedRows = rowsCompletedPerBand[ty] or 0
		tiles[ty][tx] = string.rep("\n", completedRows)
	end
end

---------------------------------------------------------------------
-- Main slicer
---------------------------------------------------------------------
function utils:sliceRichText(str: string)
	-- Optional: keep if you want normalization here
	str = utils:NormalizeText(str)

	local tokens = tokenizeRichText(str)

	local tiles = {}

	-- Visible grid position
	local visibleRow = 1
	local visibleCol = 1

	-- Per-tileY row counts for vertical alignment
	local rowsCompletedPerBand = {}

	-- Tag stack
	local openTags = {}

	-----------------------------------------------------------------
	-- Tile coordinate helpers
	-----------------------------------------------------------------
	local function getTileCoordsFor(row: number, col: number)
		local tileY = math.floor((row - 1) / utils.ROWS_PER_NOTE) + 1
		local tileX = math.floor((col - 1) / utils.COLS_PER_NOTE) + 1
		return tileY, tileX
	end

	local function getTileCoords()
		return getTileCoordsFor(visibleRow, visibleCol)
	end

	local currentTileY, currentTileX = getTileCoords()

	-----------------------------------------------------------------
	-- Append helpers
	-----------------------------------------------------------------
	local function appendToTile(text: string, ty: number, tx: number)
		ensureTile(tiles, ty, tx, rowsCompletedPerBand)
		tiles[ty][tx] ..= text
	end

	local function closeAllTagsInTile(ty: number?, tx: number?)
		if not ty or not tx then return end
		if #openTags == 0 then return end

		ensureTile(tiles, ty, tx, rowsCompletedPerBand)
		for i = #openTags, 1, -1 do
			tiles[ty][tx] ..= "</" .. openTags[i].name .. ">"
		end
	end

	local function reopenAllTagsInTile(ty: number?, tx: number?)
		if not ty or not tx then return end
		if #openTags == 0 then return end

		ensureTile(tiles, ty, tx, rowsCompletedPerBand)
		for i = 1, #openTags do
			tiles[ty][tx] ..= openTags[i].full
		end
	end

	-----------------------------------------------------------------
	-- Safe tile switching
	-----------------------------------------------------------------
	local function switchTile(ty: number, tx: number)
		if ty == currentTileY and tx == currentTileX then
			return
		end

		-- Close tags in old tile
		closeAllTagsInTile(currentTileY, currentTileX)

		-- Move
		currentTileY, currentTileX = ty, tx

		-- Reopen tags in new tile
		reopenAllTagsInTile(currentTileY, currentTileX)
	end

	-----------------------------------------------------------------
	-- PROCESS TOKENS
	-----------------------------------------------------------------
	for _, token in ipairs(tokens) do
		if isTag(token) then
			-------------------------------------------------------------
			-- TAG TOKEN
			-------------------------------------------------------------
			local name = getTagName(token)
			local closing = isClosingTag(token)

			local ty, tx = getTileCoords()
			switchTile(ty, tx)

			-- Write tag into current tile
			appendToTile(token, ty, tx)

			if closing then
				-- Pop AFTER writing the closing tag
				for i = #openTags, 1, -1 do
					if openTags[i].name == name then
						table.remove(openTags, i)
						break
					end
				end
			else
				-- Push AFTER writing the opening tag
				table.insert(openTags, { name = name, full = token })
			end

		elseif token == "\n" then
			-------------------------------------------------------------
			-- NEWLINE TOKEN (band-based, deterministic)
			-------------------------------------------------------------
			local tileY = math.floor((visibleRow - 1) / utils.ROWS_PER_NOTE) + 1
			rowsCompletedPerBand[tileY] = rowsCompletedPerBand[tileY] or 0

			local rowTiles = tiles[tileY]
			if rowTiles then
				-- Collect tile indices in sorted order to guarantee left-to-right
				local keys = {}
				for k in pairs(rowTiles) do
					table.insert(keys, k)
				end
				table.sort(keys)

				-- Append newline to each existing tile in this band
				for _, tx in ipairs(keys) do
					ensureTile(tiles, tileY, tx, rowsCompletedPerBand)
					tiles[tileY][tx] ..= "\n"
				end
			else
				-- No tiles yet in this band: only touch the tile we're actually in
				local ty, tx = getTileCoords()
				ensureTile(tiles, ty, tx, rowsCompletedPerBand)
				tiles[ty][tx] ..= "\n"
			end

			-- Increment band row count
			rowsCompletedPerBand[tileY] += 1

			-- Advance row
			visibleRow += 1
			visibleCol = 1

			-- Switch tile if needed
			local newTy, newTx = getTileCoords()
			switchTile(newTy, newTx)

		else
			-------------------------------------------------------------
			-- VISIBLE CHARACTER
			-------------------------------------------------------------
			local ty, tx = getTileCoords()
			switchTile(ty, tx)
			appendToTile(token, ty, tx)

			visibleCol += 1
		end
	end

	-----------------------------------------------------------------
	-- Close tags in final tile
	-----------------------------------------------------------------
	closeAllTagsInTile(currentTileY, currentTileX)

	local rows = #tiles

	for ty, row in pairs(tiles) do
		local cols = #row
		for tx, tile in pairs(row) do
			--if tx == cols or ty == row then
				--print("last edge tile")
				local removed = utils:RemoveRichText(tile)
				local removed2 = pystring.strip(removed, "\n")
				if removed2 == "" then
					--print("empty tile", tile, removed, removed2)
					tiles[ty][tx] = nil
				end
			--end
		end
	end

	return tiles
end

--More primitive to get TextBounds, has SizeConstraints, has less Fonts (I don't think this ignores Rich Text tags)
function utils:GetTextSize(text: string, fontSize: number, font: Enum.Font, frameAbsoluteSize: Vector2): Vector2
	return TextService:GetTextSize(text, fontSize, font, frameAbsoluteSize)
end

--More robust way to get TextBounds, has no SizeConstraints, has more Fonts (This seems to ignore Rich Text tags)
function utils:GetTextBoundsAsync(text: string, fontSize: number, width: number, richText: boolean?): Vector2?
	local params = Instance.new("GetTextBoundsParams")
	params.RichText = richText or true
	params.Text = text
	params.Font = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
	params.Size = fontSize
	params.Width = width

	local success, bounds = pcall(function()
		return TextService:GetTextBoundsAsync(params)
	end)
	if success then
		return bounds
	else
		params.RichText = false
		local success, bounds = pcall(function()
			return TextService:GetTextBoundsAsync(params)
		end)
		if success then
			return bounds
		else
			return nil
		end
	end
end

if RunService:IsServer() then
	local HttpService = game:GetService("HttpService")
	function utils:FilterTextAsync(text: string, fromUserId: number): string?
		local filterResult: TextFilterResult
		local success, errorMessage = pcall(function()
			filterResult = TextService:FilterStringAsync(utils:RemoveRichText(text), fromUserId, Enum.TextFilterContext.PublicChat)
		end)

		if success then
			if filterResult then
				local ok, safeText = pcall(function()
					return filterResult:GetNonChatStringForBroadcastAsync()
				end)
				if ok then
					if utils:IsOnlyHashtags(safeText) then
						--warn("Text was filtered, but returned text is all hashtags.")
						--If text was filtered, return the filtered hashtags string
						return safeText
					else
						--warn("Text was filtered, but returned text is not all hashtags.")
						--If the text is not all hashtags (aka filtered), then just return the raw richtext version
						return text
					end
				else
					warn(safeText)
					return nil
				end
			end
		else
			warn("Error generating TextFilterResult:", errorMessage)
			return nil
		end
	end
end

return utils