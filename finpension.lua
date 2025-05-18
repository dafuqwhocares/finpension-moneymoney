--------------------------------------------------------------------------------
-- Finpension 3a Extension for MoneyMoney https://moneymoney-app.com
-- Copyright 2025 Ansgar Scheffold
--------------------------------------------------------------------------------
WebBanking {
    version     = 1.00,
    url         = "https://accounts.finpension.ch",
    services    = {"Finpension 3a"},
    description = "Finpension 3a Konten in MoneyMoney anzeigen"
}

local authBaseUrl = "https://accounts.finpension.ch/api"
local apiBaseUrl = "https://3a.finpension.ch/api"
local connection = nil
local authToken = nil

-- Tabelle mit Ländercodes basierend auf Vorwahlen
local countryCodes = {
  ["1"] = "US",  -- USA
  ["41"] = "CH", -- Schweiz
  ["43"] = "AT", -- Österreich
  ["44"] = "GB", -- Großbritannien
  ["49"] = "DE", -- Deutschland
  ["33"] = "FR", -- Frankreich
  ["34"] = "ES", -- Spanien
  ["39"] = "IT", -- Italien
  ["31"] = "NL", -- Niederlande
  ["32"] = "BE", -- Belgien
  ["45"] = "DK", -- Dänemark
  ["46"] = "SE", -- Schweden
  ["47"] = "NO", -- Norwegen
  ["48"] = "PL", -- Polen
  ["351"] = "PT", -- Portugal
  ["352"] = "LU", -- Luxemburg
  ["353"] = "IE", -- Irland
  ["358"] = "FI", -- Finnland
  ["420"] = "CZ", -- Tschechien
  ["421"] = "SK"  -- Slowakei
}

-- Debug-Einstellungen
local DEBUG_MODE = true

-- Hilfsfunktion zum Loggen
local function log(message)
  if DEBUG_MODE then
    print(extensionName .. ": " .. message)
  end
end

function SupportsBank (protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == "Finpension 3a"
end

-- Funktion zur Extraktion des Ländercodes aus der Telefonnummer
function ExtractCountryCode(phoneNumber)
  if not phoneNumber or phoneNumber:sub(1, 1) ~= "+" then
    return nil
  end
  
  phoneNumber = phoneNumber:sub(2) -- "+" entfernen
  
  -- Bekannte dreistellige Vorwahlen prüfen
  for prefix, code in pairs(countryCodes) do
    if phoneNumber:sub(1, #prefix) == prefix then
      return code
    end
  end
  
  -- Bekannte zweistellige Vorwahlen prüfen
  for i = 2, 1, -1 do
    local prefix = phoneNumber:sub(1, i)
    if countryCodes[prefix] then
      return countryCodes[prefix]
    end
  end
  
  return nil
end

function InitializeSession (protocol, bankCode, username, reserved, password)
  log("InitializeSession aufgerufen für Finpension 3a")
  
  connection = Connection()
  connection.language = "de"
  
  -- HTTP Header setzen wie im Browser-Request
  local headers = {
    ["Accept"] = "*/*",
    ["Accept-Language"] = "de",
    ["x-app-version"] = "6.1.5",
    ["x-app-platform"] = "web",
    ["Origin"] = "https://app.finpension.ch",
    ["Content-Type"] = "application/json"
  }
  
  -- Ländercode aus der Telefonnummer extrahieren
  local countryCode = ExtractCountryCode(username)
  if not countryCode then
    return "Konnte Ländercode nicht aus der Telefonnummer extrahieren. Verwende das Format +49... für die Telefonnummer."
  end
  
  -- Login-Daten aus der Anfrage
  local postContent = JSON():set({
    country_code = countryCode,
    password = password,
    server = "",
    mobile_number = username
  }):json()
  
  -- Login-Anfrage senden
  local content, charset, mimeType, filename, responseHeaders = connection:request(
    "POST", 
    authBaseUrl .. "/login", 
    postContent, 
    "application/json", 
    headers
  )
  
  -- Antwort auswerten
  local jsonResponse = JSON(content):dictionary()
  
  if jsonResponse and jsonResponse.token then
    -- Token für weitere Anfragen speichern
    authToken = jsonResponse.token
    log("Login erfolgreich, Token erhalten")
    return nil -- Erfolgreiche Anmeldung
  else
    log("Login fehlgeschlagen")
    return LoginFailed
  end
end

function ListAccounts (knownAccounts)
  log("ListAccounts aufgerufen")
  
  local headers = {
    ["Accept"] = "application/json",
    ["Authorization"] = "Bearer " .. authToken,
    ["x-app-version"] = "6.1.5",
    ["x-app-platform"] = "web",
    ["Origin"] = "https://app.finpension.ch"
  }
  
  -- Anfrage für Kontoinformationen an den richtigen API-Endpunkt
  local content, charset, mimeType = connection:request(
    "GET", 
    apiBaseUrl .. "/portfolios",
    nil, 
    nil, 
    headers
  )
  
  local portfolioList = JSON(content):dictionary()
  
  if not portfolioList or not portfolioList[1] then
    log("Keine Portfolios gefunden")
    return {} -- Keine Konten gefunden
  end
  
  log("Anzahl gefundener Portfolios: " .. #portfolioList)
  
  local accounts = {}
  
  for _, portfolio in ipairs(portfolioList) do
    local account = {
      name = "Finpension Portfolio " .. (portfolio.number or ""),
      owner = portfolio.id and ("ID: " .. portfolio.id) or "Finpension 3a",
      accountNumber = tostring(portfolio.id),
      portfolio = true, -- Als Depot markieren
      bankCode = "Finpension 3a",
      currency = "CHF",
      type = AccountTypePortfolio -- Kontotyp auf Depot setzen
    }
    
    log("Erstelle MoneyMoney Konto für Portfolio: " .. account.name .. " (ID: " .. account.accountNumber .. ")")
    table.insert(accounts, account)
  end
  
  return accounts
end

function RefreshAccount (account, since)
  log("RefreshAccount aufgerufen für MoneyMoney-Konto: " .. account.name .. " (ID: " .. account.accountNumber .. ")")
  
  local headers = {
    ["Accept"] = "application/json",
    ["Authorization"] = "Bearer " .. authToken,
    ["x-app-version"] = "6.1.5",
    ["x-app-platform"] = "web",
    ["Origin"] = "https://app.finpension.ch"
  }
  
  local content, charset, mimeType = connection:request(
    "GET", 
    apiBaseUrl .. "/portfolios",
    nil, 
    nil, 
    headers
  )
  
  local portfolioList = JSON(content):dictionary()
  local portfolioData = nil
  for _, portfolio in ipairs(portfolioList) do
    if tostring(portfolio.id) == account.accountNumber then
      portfolioData = portfolio
      break
    end
  end

  if not portfolioData or not portfolioData.performance or not portfolioData.allocation_by_asset_class then
    log("Keine Portfoliodaten für Konto " .. account.accountNumber .. " gefunden")
    return {balance = 0, securities = {}} 
  end

  local balance = tonumber(portfolioData.performance.current_value) or 0
  local securities = {}
  local purchaseTimestamp = nil
  
  if portfolioData.transactions and #portfolioData.transactions > 0 then
    for _, transaction in ipairs(portfolioData.transactions) do
      if transaction.type == "deposit" and transaction.date then
        local y, m, d = string.match(transaction.date, "(%d+)%-(%d+)%-(%d+)")
        if y and m and d then
          local ts = os.time({year=tonumber(y), month=tonumber(m), day=tonumber(d)})
          if not purchaseTimestamp or ts < purchaseTimestamp then
            purchaseTimestamp = ts
          end
        end
      end
    end
  end
  
  if not purchaseTimestamp and portfolioData.created_at then
    local y, m, d = string.match(portfolioData.created_at, "(%d+)%-(%d+)%-(%d+)")
    if y and m and d then
      purchaseTimestamp = os.time({year=tonumber(y), month=tonumber(m), day=tonumber(d)})
    end
  end
  
  if not purchaseTimestamp then
    purchaseTimestamp = os.time() - 365*24*60*60 
  end
  
  local function findIsinByAssetName(name, strategyCategories)
    if not strategyCategories then return nil end
    for _, category in ipairs(strategyCategories) do
      if category.positions then
        for _, pos in ipairs(category.positions) do
          if pos.asset_name == name and pos.isin and pos.isin ~= "" then
            return pos.isin
          end
        end
      end
    end
    return nil
  end
  
  for _, assetClass in ipairs(portfolioData.allocation_by_asset_class) do
    if assetClass.positions then
      for _, position in ipairs(assetClass.positions) do
        local assetName = position.asset_name
        local assetValue = tonumber(position.value) or 0
        local assetShares = tonumber(position.shares) or 0
        local security = {}
        
        if assetName == "Cash" then
          security = {
            name = "Liquidität",
            quantity = 1,
            currencyOfQuantity = nil, -- Explizit nil für Stückzahl
            price = assetValue,
            currencyOfPrice = "CHF", -- Explizit CHF
            amount = assetValue,
            securityNumber = account.accountNumber .. "-CASH",
            tradeTimestamp = os.time()
          }
          log("Liquidität: " .. security.name .. ", Menge: " .. security.quantity .. ", Preis: " .. security.price .. " CHF")
        else
          local assetPrice = 0
          if assetShares > 0 then
            assetPrice = assetValue / assetShares
          end
          
          local isin = findIsinByAssetName(assetName, portfolioData.strategy and portfolioData.strategy.categories)
          local estimatedPurchasePrice = assetPrice
          
          if portfolioData.performance and portfolioData.performance.current_profit_value then
            local profit = tonumber(portfolioData.performance.current_profit_value) or 0
            local deposits = tonumber(portfolioData.performance.deposits_ytd) or 0
            if deposits > 0 and profit ~= 0 then 
              local profitRatio = profit / deposits
              estimatedPurchasePrice = assetPrice / (1 + profitRatio) 
            end
          end
          
          security = {
            name = assetName,
            isin = isin,
            quantity = assetShares,
            currencyOfQuantity = nil, -- Explizit nil für Stückzahl
            price = assetPrice,
            currencyOfPrice = "CHF", -- Explizit CHF
            purchasePrice = estimatedPurchasePrice,
            currencyOfPurchasePrice = "CHF", -- Explizit CHF
            amount = assetValue,
            purchaseDate = purchaseTimestamp,
            tradeTimestamp = os.time()
          }
          log("Wertpapier: " .. security.name .. ", Menge: " .. security.quantity .. ", Preis: " .. security.price .. " CHF, Kaufpreis: " .. security.purchasePrice .. " CHF")
        end
        table.insert(securities, security)
      end
    end
  end
  
  log("Konto " .. account.accountNumber .. ": Saldo " .. balance .. ", " .. #securities .. " Wertpapiere")
  return {
    balance = balance,
    securities = securities
  }
end

function EndSession ()
  log("EndSession aufgerufen")
  
  -- Abmeldung
  if connection and authToken then
    local headers = {
      ["Authorization"] = "Bearer " .. authToken,
      ["x-app-version"] = "6.1.5",
      ["x-app-platform"] = "web",
      ["Origin"] = "https://app.finpension.ch"
    }
    
    connection:request(
      "POST", 
      authBaseUrl .. "/logout", 
      "", 
      "application/json", 
      headers
    )
    
    log("Logout-Anfrage gesendet")
    authToken = nil
  end
  
  if connection then
    connection:close()
    connection = nil
  end
  
  log("Session beendet")
  return nil
end

log("Finpension 3a Extension geladen.")
