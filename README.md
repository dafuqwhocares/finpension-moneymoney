# Finpension 3a Extension for MoneyMoney

Diese Web Banking Extension ermöglicht den Zugriff auf die Portfolios bei Finpension Säule 3a (CH) in MoneyMoney.

## Funktionen

- **Zugriff auf Portfolios:**  
  Die Extension ermöglicht den Zugriff auf Ihre Finpension 3a Portfolios.
- **Automatische Portfolio-Erkennung:**  
  Vorhandene Portfolios werden automatisch erkannt und in MoneyMoney hinzugefügt.
- **Anzeige von Vermögenswerten:**  
  Detaillierte Auflistung der investierten Fonds und anderer Vermögenswerte.
- **Anzeige liquider Mittel:**  
  Der aktuelle Cash-Bestand (liquide Mittel) des Kontos wird angezeigt.
- **Gesamter Kontostand:**  
  Der gesamte aktuelle Wert des Portfolios wird ausgegeben.

## Aktuelle Einschränkungen

- Sessions werden derzeit nicht persistiert. Das bedeutet, dass beim Start jeder neuen Sitzung erneut ein SMS-Code eingegeben werden muss.

## Installation und Nutzung

### Betaversion installieren

Diese Extension funktioniert ausschließlich mit Beta-Versionen von MoneyMoney. Eine signierte Version kann auf der offiziellen Website heruntergeladen werden: https://moneymoney.app/extensions/

### Installation

1. **Öffne MoneyMoney** und gehe zu den Einstellungen (Cmd + ,).
2. Gehe in den Reiter **Extensions** und deaktiviere ggf. den Haken bei **"Digitale Signaturen von Erweiterungen überprüfen"**, falls Probleme beim Laden der Extension auftreten.
3. Wähle im Menü **Ablage > Datenbank im Finder zeigen**. (Hinweis: Der Menüpunkt kann je nach MoneyMoney Version leicht anders heissen, z.B. unter "Hilfe")
4. Kopiere die Datei `Finpension.lua` aus diesem Repository in den Ordner `Extensions`:
   `~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions`
5. Starte MoneyMoney neu. Beim Hinzufügen eines neuen Kontos sollte nun der Service-Typ **Finpension 3a** (oder ähnlich) erscheinen.

## Lizenz

Diese Software wird unter der **MIT License mit dem Commons Clause Zusatz** bereitgestellt.  
Das bedeutet, dass Änderungen und Weiterverteilungen (auch modifizierte Versionen) erlaubt sind – eine kommerzielle Nutzung bzw. der Verkauf der Software oder abgeleiteter Werke ist jedoch ohne die ausdrückliche Zustimmung des Autors untersagt. 
