# BSI-Sicherheitshinweise als STIX 2.1 für OpenCTI

Prototyp zu einer Bachelorarbeit an der Technischen Hochschule Brandenburg (2026):
*Untersuchung von Automatisierungspotenzialen bei der Aufbereitung von BSI-Bedrohungsinformationen für Cyber-Threat-Intelligence-Plattformen am Beispiel von OpenCTI*.

Die Pipeline liest die Sicherheitshinweise des Warn- und Informationsdienstes (WID) von CERT-Bund,
reichert sie mit den zugehörigen CSAF-2.0-Dokumenten an und erzeugt daraus STIX-2.1-Bundles,
die sich in OpenCTI importieren lassen.

## Ablauf

```
RSS-Feed des WID ──► Basisvariante:        Identity + Report
        │
        └─► CSAF-Dokument ──► angereicherte Variante: Identity + Report
                                + Vulnerability (je CVE)
                                + Software (je betroffenem Produkt)
                                + Relationship "has" (Software → Vulnerability)
```

Je Meldung entstehen zwei Bundles: eine Basisvariante nur aus dem Feed und eine angereicherte
Variante mit den Daten aus dem CSAF-Dokument. Die Zuordnung der Felder steht in
[`docs/mapping_wid_stix.txt`](docs/mapping_wid_stix.txt).

## Inhalt

| Datei / Ordner | Inhalt | Abschnitt der Arbeit |
|---|---|---|
| `pipeline.ipynb` | Pipeline: Feed lesen, CSAF abrufen, STIX-Bundles erzeugen, Kennzahlen schreiben | Kap. 5 |
| `auswertung.ipynb` | Auswertung der Kennzahlen aus `data/stats.csv` | 6.2 |
| `validierung.ipynb` | Prüfung aller Bundles mit dem OASIS STIX Validator | 6.4 |
| `korrektheit.ipynb` | Abgleich der Bundles mit den CSAF-Dokumenten für alle Meldungen | 6.5 |
| `data/raw/` | Gesicherte Rohdaten (RSS-Einträge und CSAF-Dokumente) | A9 |
| `data/bundles_final/` | Die ausgewerteten 500 Bundles (250 Meldungen × 2 Varianten) | Kap. 6 |
| `data/stats.csv` | Kennzahlen je Meldung und Lauf | 6.2 |
| `results/validation_results.csv` | Ergebnis der Validierung je Bundle | 6.4 |
| `opencti/opencti_setup.sh` | Richtet eine lokale OpenCTI-Instanz mit Docker ein | 5.6, 6.6 |
| `docs/` | Feldzuordnung WID → STIX | 4.4 |

## Installation

Getestet mit Python 3.10 auf macOS.

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Die TLS-Zertifikate werden über die Zertifikatsverwaltung des Betriebssystems geprüft
(Bibliothek `truststore`). Eine Abschaltung der Prüfung ist nicht vorgesehen.

## Ausführen

**Pipeline:** `pipeline.ipynb` öffnen und die Zellen der Reihe nach ausführen.
Neue Bundles landen in `data/bundles/`, Rohdaten in `data/raw/`, Kennzahlen in `data/stats.csv`.
Der Meldungsbestand in `data/state.json` sorgt dafür, dass bereits verarbeitete Meldungen
beim nächsten Lauf übersprungen werden. Für einen kompletten Neulauf die Datei löschen.

**Evaluation nachvollziehen** (ohne erneuten Abruf beim BSI):

1. `pipeline.ipynb`: Die Zelle zur Neuerzeugung erzeugt die Bundles aus `data/raw/` neu und
   vergleicht die Objektzahlen mit `data/stats.csv`.
2. `validierung.ipynb`: prüft alle Bundles in `data/bundles_final/`.
   Beim ersten Start lädt das Notebook die JSON-Schemas von OASIS nach.
3. `korrektheit.ipynb`: vergleicht alle Bundles mit den CSAF-Dokumenten.
4. `auswertung.ipynb`: erzeugt die Kennzahlen und Abbildungen aus Kapitel 6.

**Import in OpenCTI:**

```bash
cd opencti
sh opencti_setup.sh      # erzeugt docker-compose.yml, .env und rabbitmq.conf
docker compose up -d
```

Die Zugangsdaten stehen danach in `opencti/.env`. Diese Datei wird nicht versioniert.
Die Bundles lassen sich in OpenCTI unter *Data → Import* hochladen.
Getestet mit OpenCTI 7.261002.0.

## Ergebnisse (Lauf September 2026, 250 Meldungen)

- 500 von 500 Bundles ohne Fehler im OASIS STIX Validator 3.3.1
- Korrektheitsprüfung aller 250 Meldungen ohne Abweichung
  (8.344 CVE-Kennungen, 2.366 betroffene Produkte, 101.915 Zuordnungen)
- Wiederholter Import in OpenCTI ohne Dopplungen

## Bekannte Einschränkungen

- CVSS-Werte werden nicht abgebildet. Das Feld `scores` ist in den CSAF-Dokumenten des BSI nicht befüllt.
- Eigene Felder (`x_…`) bleiben im Bundle erhalten, werden von OpenCTI beim Import aber nicht übernommen.
- Fehlt am betroffenen Produkt eine CPE-Kennung, wird die CPE der behobenen Version übernommen und
  als abgeleitet markiert. Die Versionsangabe darin wird derzeit nicht angepasst.
- Die Kennungen der Software-Objekte werden aus dem Produktnamen gebildet und weichen damit von der
  Empfehlung der STIX-Spezifikation ab (siehe Abschnitt 5.7 der Arbeit).

## Datenquelle

Die Rohdaten stammen aus dem öffentlich zugänglichen Warn- und Informationsdienst von CERT-Bund
(BSI): <https://wid.cert-bund.de>.
