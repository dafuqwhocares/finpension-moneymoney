--------------------------------------------------------------------------------
-- Finpension 3a Extension for MoneyMoney https://moneymoney-app.com
-- Copyright 2025 Ansgar Scheffold
--------------------------------------------------------------------------------
WebBanking {
  version     = 1.10,
  url         = "https://accounts.finpension.ch",
  services    = {"Finpension 3a"},
  description = "Finpension 3a Konten in MoneyMoney anzeigen (mit SMS-2FA)"
}

local authBaseUrl = "https://accounts.finpension.ch/api"
local apiBaseUrl  = "https://3a.finpension.ch/api"

local connection  = nil
local authToken   = nil
local msisdn      = nil      -- +49..., wird aus username übernommen
local countryCode = nil      -- "DE", "CH", ...
local cachedPassword = nil

local DEBUG_MODE  = false
local function log(msg)
  if DEBUG_MODE then print(extensionName .. ": " .. msg) end
end

-- Ländercodes (Auszug)
local countryCodes = {
  ["1"]   = "US",
  ["33"]  = "FR",
  ["34"]  = "ES",
  ["39"]  = "IT",
  ["41"]  = "CH",
  ["43"]  = "AT",
  ["44"]  = "GB",
  ["45"]  = "DK",
  ["46"]  = "SE",
  ["47"]  = "NO",
  ["48"]  = "PL",
  ["49"]  = "DE",
  ["31"]  = "NL",
  ["32"]  = "BE",
  ["351"] = "PT",
  ["352"] = "LU",
  ["353"] = "IE",
  ["358"] = "FI",
  ["420"] = "CZ",
  ["421"] = "SK"
}

local function extractCountryCode(e164)
  if not e164 or e164:sub(1,1) ~= "+" then return nil end
  local digits = e164:sub(2)
  -- Longest prefix match (3 → 2 → 1)
  for len = 3, 1, -1 do
    local prefix = digits:sub(1, len)
    if countryCodes[prefix] then return countryCodes[prefix] end
  end
  return nil
end

local function headers(extra, withAuth, withReferer)
  local h = {
    ["Accept"]         = "application/json",
    ["Content-Type"]   = "application/json",
    ["x-app-version"]  = "6.1.5",
    ["x-app-platform"] = "web",
    ["Origin"]         = "https://app.finpension.ch"
  }
  if withAuth and authToken then
    h["Authorization"] = "Bearer " .. authToken
  end
  if withReferer then
    h["Referer"] = "https://app.finpension.ch/login"
  end
  if extra then
    for k,v in pairs(extra) do h[k]=v end
  end
  return h
end

function SupportsBank (protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == "Finpension 3a"
end

-- Zwei-Faktor-Login
-- step=1: credentials[1]=username (MSISDN), credentials[2]=password
-- step=2: credentials[1]=SMS-Code (Antwort auf challenge)
function InitializeSession2 (protocol, bankCode, step, credentials, interactive)
  if step == 1 then
    log("InitializeSession2 step 1")
    connection = Connection()
    connection.language = "de-DE"
    connection.useragent = "Mozilla/5.0 (compatible; " .. MM.productName .. "/" .. MM.productVersion .. ")"

    msisdn      = credentials[1]
    local password = credentials[2]
    cachedPassword = password -- für step 2 merken
    countryCode = extractCountryCode(msisdn)

    if not countryCode then
      return "Konnte Ländercode nicht aus der Telefonnummer extrahieren. Bitte im Format +49..., +41..., etc. angeben."
    end
    if (not password) or password == "" then
      return "Leeres Passwort."
    end

    local body = JSON():set({
      country_code  = countryCode,
      password      = password,
      server        = "",
      mobile_number = msisdn
    }):json()

    local content, charset, mimeType, filename, respHeaders =
      connection:request("POST", authBaseUrl .. "/login", body, "application/json", headers(nil, false))

    -- /login liefert bei SMS-2FA typischerweise {"message":"OK","method":"sms"}
    local ok, data = pcall(function() return JSON(content):dictionary() end)
    if ok and data then
      if data.token then
        -- (falls jemals direkt ein Token kommt – akzeptieren)
        authToken = data.token
        log("Token bereits nach /login erhalten (ohne 2FA).")
        return nil
      end
      if (data.method == "sms") or (data.message == "OK") then
        -- TAN-Dialog anzeigen
        return {
          title     = "SMS-Code erforderlich",
          challenge = "Es wurde ein SMS-Code an " .. msisdn .. " gesendet.\nBitte hier eingeben:",
          label     = "SMS-Code"
        }
      end
    end

    -- Fehlerfall: versuche sinnvolle Meldung
    log("Unerwartete /login-Antwort. Abbruch.")
    return LoginFailed

  elseif step == 2 then
    log("InitializeSession2 step 2 (verify SMS)")
    local smsCode = credentials[1]
    if (not smsCode) or smsCode == "" then
      return "Kein SMS-Code eingegeben."
    end

    local needsPasswordIn2FA = true

    if needsPasswordIn2FA and (not cachedPassword or cachedPassword == "") then
      return "Passwort nicht verfügbar für 2FA. Bitte den Login erneut starten."
    end

    local body = {
      mobile_number = msisdn,
      country_code  = countryCode,
      code          = smsCode
    }
    if needsPasswordIn2FA then
      body.password = cachedPassword
    end

    local content = select(1, connection:request(
      "POST",
      authBaseUrl .. "/login2fa",
      JSON():set(body):json(),
      "application/json",
      headers(nil, false)
    ))

    local data = JSON(content):dictionary()
    if not data or not data.token then
      log("Kein Token in /login2fa-Antwort.")
      return LoginFailed
    end

    authToken = data.token
    cachedPassword = nil
    log("2FA erfolgreich, Token erhalten.")
    return nil
  end
end

-- Optional: Standard-Login (ohne TAN-Dialog) InitializeSession als Proxy nutzen, um Passwort kurz zu puffern.
function InitializeSession (protocol, bankCode, username, reserved, password)
  -- Passwort temporär sichern, damit InitializeSession2/step2 es verwenden kann:
  if password and password ~= "" then
    LocalStorage:write("finpension3a_tmp_pw", password)
  end
  -- MoneyMoney ruft danach automatisch InitializeSession2 step=1 auf.
  return nil
end

-- Kontoliste
function ListAccounts (knownAccounts)
  log("ListAccounts")
  if not authToken then
    return "Nicht authentifiziert (kein Token)."
  end

  local content = nil
  local ok, err = pcall(function()
    content = select(1, connection:request("GET", apiBaseUrl .. "/portfolios", nil, nil, headers(nil, true)))
  end)
  if not ok then
    log("Fehler /portfolios: " .. tostring(err))
    return "Portfolios konnten nicht geladen werden."
  end

  local portfolios = JSON(content):dictionary()
  if type(portfolios) ~= "table" or #portfolios == 0 then
    log("Keine Portfolios gefunden")
    return {}
  end

  local accounts = {}
  for _, p in ipairs(portfolios) do
    local nr = p.number and tostring(p.number) or "?"
    local id = p.id and tostring(p.id) or ""
    local acc = {
      name          = "Finpension Portfolio " .. nr,
      owner         = p.id and ("ID: " .. id) or "Finpension 3a",
      accountNumber = id,
      portfolio     = true,
      bankCode      = "Finpension 3a",
      currency      = "CHF",
      type          = AccountTypePortfolio
    }
    table.insert(accounts, acc)
  end
  return accounts
end

-- Depotbestand eines Kontos
function RefreshAccount (account, since)
  log("RefreshAccount: " .. (account.name or "?") .. " #" .. (account.accountNumber or "?"))

  local content = nil
  local ok, err = pcall(function()
    content = select(1, connection:request("GET", apiBaseUrl .. "/portfolios", nil, nil, headers(nil, true)))
  end)
  if not ok then
    log("Fehler /portfolios: " .. tostring(err))
    return { balance = 0, securities = {} }
  end

  local list = JSON(content):dictionary()
  local pData = nil
  for _, p in ipairs(list or {}) do
    if tostring(p.id) == account.accountNumber then pData = p; break end
  end
  if not pData then
    log("Portfolio nicht gefunden.")
    return { balance = 0, securities = {} }
  end

  local balance = tonumber(pData.performance and pData.performance.current_value) or 0
  local secs = {}

  local function earliestDepositTs(portfolio)
    local ts = nil
    if portfolio.transactions then
      for _, t in ipairs(portfolio.transactions) do
        if t.type == "deposit" and t.date then
          local y,m,d = t.date:match("(%d+)%-(%d+)%-(%d+)")
          if y then
            local t0 = os.time({year=tonumber(y), month=tonumber(m), day=tonumber(d)})
            ts = (not ts or t0 < ts) and t0 or ts
          end
        end
      end
    end
    if (not ts) and portfolio.created_at then
      local y,m,d = portfolio.created_at:match("(%d+)%-(%d+)%-(%d+)")
      if y then ts = os.time({year=tonumber(y), month=tonumber(m), day=tonumber(d)}) end
    end
    return ts or (os.time() - 365*24*60*60)
  end

  local purchaseTs = earliestDepositTs(pData)

  local function findIsinByName(name, cats)
    if not cats then return nil end
    for _, c in ipairs(cats) do
      if c.positions then
        for _, pos in ipairs(c.positions) do
          if pos.asset_name == name and pos.isin and pos.isin ~= "" then
            return pos.isin
          end
        end
      end
    end
    return nil
  end

  -- Positionen aus allocation_by_asset_class ziehen
  for _, cls in ipairs(pData.allocation_by_asset_class or {}) do
    for _, pos in ipairs(cls.positions or {}) do
      local name   = pos.asset_name
      local value  = tonumber(pos.value) or 0
      local shares = tonumber(pos.shares) or 0

      if name == "Cash" then
        table.insert(secs, {
          name                 = "Liquidität",
          quantity             = 1,
          currencyOfQuantity   = nil,
          price                = value,
          currencyOfPrice      = "CHF",
          amount               = value,
          securityNumber       = (account.accountNumber .. "-CASH"),
          tradeTimestamp       = os.time()
        })
      else
        local price = (shares > 0) and (value / shares) or 0
        local isin  = findIsinByName(name, pData.strategy and pData.strategy.categories)

        -- grobe Kaufkurs-Schätzung über Verhältnis Gewinn/Einzahlung
        local estPurchasePrice = price
        if pData.performance then
          local profit   = tonumber(pData.performance.current_profit_value or 0) or 0
          local deposits = tonumber(pData.performance.deposits_ytd or 0) or 0
          if deposits > 0 and profit ~= 0 then
            local ratio = profit / deposits
            estPurchasePrice = price / (1 + ratio)
          end
        end

        table.insert(secs, {
          name                      = name,
          isin                      = isin,
          quantity                  = shares,
          currencyOfQuantity        = nil,
          price                     = price,
          currencyOfPrice           = "CHF",
          purchasePrice             = estPurchasePrice,
          currencyOfPurchasePrice   = "CHF",
          amount                    = value,
          purchaseDate              = purchaseTs,
          tradeTimestamp            = os.time()
        })
      end
    end
  end

  return {
    balance    = balance,
    securities = secs
  }
end

function EndSession ()
  log("EndSession")
  if connection and authToken then
    pcall(function()
      connection:request("POST", authBaseUrl .. "/logout", "", "application/json", headers(nil, true))
      log("Logout gesendet")
    end)
  end
  authToken = nil
  if connection then pcall(function() connection:close() end); connection = nil end
  return nil
end

log("Finpension 3a Extension (2FA) geladen.")
