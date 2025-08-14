Der KPN LISA-Target-Connector verbindet KPN LISA mit der Identity & Access Management (IAM)-Lösung HelloID von Tools4ever an verschiedene Quellsysteme. Das ist vorteilhaft, da Sie so die Verwaltung von Benutzerkonten und Berechtigungen in KPN-Arbeitsplätzen automatisieren können. Daten aus Ihrem Quellsystem sind dabei immer maßgeblich, was Fehler verhindert. Sie sparen Zeit, unterstützen Ihre Organisation optimal und erhöhen die Benutzerzufriedenheit.

## Was ist KPN LISA?

KPN LISA ist der Name des KPN-Arbeitsplatz-Self-Service-Moduls, das auf die Verwaltung aller Formen von KPN-Arbeitsplätzen ausgerichtet ist. Das Modul unterstützt IT-Administratoren bei der Verwaltung und Absicherung von Benutzerkonten, Systemen und anderen Ressourcen in auf Microsoft Azure basierenden Firmennetzwerken. KPN LISA kann als Identity Provider (IDP) dienen und einen zentralen Zugangspunkt für im Firmennetzwerk verfügbare Ressourcen darstellen.

## Warum ist eine KPN LISA-Verbindung nützlich?

Mit dem HelloID KPN LISA-Connector können Organisationen ihre IT-Umgebung effizienter und effektiver verwalten. Der Connector spart so Zeit und Kosten und hebt gleichzeitig den gesamten Service auf ein höheres Niveau.

Der KPN LISA-Connector ermöglicht eine Verbindung zu verschiedenen beliebten Quellsystemen. Denken Sie dabei an:

* Visma Raet
* AFAS

Weitere Details zur Verbindung mit diesen Quellsystemen finden Sie weiter im Artikel.

## HelloID für KPN LISA hilft Ihnen mit

**Angemessene Verwaltung von Benutzerkonten:** Fügen Sie einen neuen Mitarbeiter zu Ihrem HR-System hinzu oder entfernen Sie einen Mitarbeiter? HelloID erkennt diese Änderung in Ihrem Quellsystem automatisch und leitet sie über den Connector an KPN LISA weiter. Basierend auf von HelloID festgelegten Arbeitsplatzprofilen führt KPN LISA dann Aktionen aus. So stellt KPN LISA beispielsweise dem Mitarbeiter ein Benutzerprofil und eine M365-Lizenz zur Verfügung. Wichtig zu beachten ist, dass HelloID die Aktion auf dem Konto ausführt und KPN LISA die Folgeaktionen übernimmt.

**Fehlerfreie Verwaltung von Berechtigungen:** Mithilfe von Berechtigungen bestimmen Sie, zu welchen Anwendungen, Systemen und Ressourcen ein Benutzer Zugang hat. Sie möchten Berechtigungen daher fehlerfrei verwalten, um sicherzustellen, dass Benutzer den richtigen Zugang haben und gleichzeitig Ihre Umgebung so sicher wie möglich halten. Dank der Verbindung zwischen HelloID und KPN LISA müssen Sie sich darum nicht kümmern. HelloID verwaltet über Business Rules die Mitgliedschaften von Lizenzprofilen und Ressourcengruppen in KPN LISA.

**Anpassen von Attributen:** Mit Gruppen bestimmen Sie auf einmal die Berechtigungen für eine Benutzergruppe. Welche Gruppenzugehörigkeiten ein Benutzer zugewiesen bekommt, hängt unter anderem von seiner Funktion und/oder Abteilung ab. Die Identifizierung dessen können Sie weitgehend automatisieren. Dieser Prozess funktioniert mithilfe von Attributen, die HelloID aus Ihrem Quellsystem abruft. Sie bestimmen selbst, auf Basis welches Attributs Sie welche Konten und Rechte in KPN LISA zuweisen möchten. Sie haben also immer die Kontrolle.

## Wie HelloID mit KPN LISA integriert

Mit Hilfe des KPN LISA Target Connectors verbinden Sie KPN LISA mit HelloID. Sie nutzen dabei einen HelloID Powershell Target Connector. HelloID kommuniziert über diesen Connector per Powershell mit den REST API Webservices von KPN LISA. Die Nutzung dieser API erfordert eine App-Registrierung im Microsoft Azure-Mandanten.

| Änderung in KPN LISA | Verfahren in den Zielsystemen |
| -------------------- | ----------------------------- |
| **Neuer Mitarbeiter** | Wenn ein neuer Mitarbeiter eintritt, soll dieser Nutzer so schnell wie möglich produktiv sein. Dies erfordert unter anderem die richtigen Konten und Berechtigungen. Die Verbindung von KPN LISA und HelloID automatisiert diesen Prozess, sodass Sie sich darum nicht kümmern müssen. So erstellt HelloID basierend auf Ihrem Quellsystem automatisch die erforderlichen Konten in KPN LISA und weist Arbeitsplatzprofile und Gruppen zu. Die zugehörigen Berechtigungen werden über KPN LISA zugewiesen. |
| **Andere Funktion Mitarbeiter** | Mitarbeiter können innerhalb einer Organisation eine neue Funktion zugewiesen bekommen. Auch kann eine bestehende Funktion neu gestaltet werden. Beide Änderungen erfordern andere Berechtigungen. Dank der Verbindung zwischen HelloID und KPN LISA erfordert dies keine manuellen Eingriffe, und HelloID passt die Arbeitsplatzprofile und Gruppen automatisch an. Die zugehörigen Berechtigungen werden über KPN LISA zugewiesen. So können Sie sicher sein, dass Benutzerkonten immer mit den aktuellen Funktionen innerhalb Ihrer Organisation übereinstimmen. |
| **Mitarbeiter scheidet aus** | Wenn ein Mitarbeiter ausscheidet, deaktiviert HelloID automatisch das Benutzerkonto in KPN LISA. Außerdem informiert die IAM-Lösung alle beteiligten Mitarbeiter. Nach einiger Zeit entfernt HelloID das KPN LISA-Konto automatisch, wodurch der Clear-Prozess in KPN LISA gestartet wird. |

## KPN LISA über HelloID mit Quellsystemen verbinden

Mithilfe von HelloID können Sie verschiedene Systeme mit KPN LISA integrieren, darunter auch zahlreiche Quellsysteme. Vorteilhaft, denn so erhöhen Sie die Effizienz bei der Verwaltung von Benutzern und Berechtigungen. Sie realisieren eine sichere und konforme Umgebung, in der Benutzer stets Zugriff auf die richtigen Systeme, Ressourcen und Daten haben. Einige Beispiele für häufige Integrationen über HelloID sind:

* **Visma Raet - KPN LISA Verbindung:** Mithilfe der Visma Raet - KPN LISA Verbindung erstellt die IAM-Lösung basierend auf allen relevanten Informationen aus dem beliebten HR-System automatisch die richtigen Benutzerkonten in KPN LISA und weist die erforderlichen Berechtigungen zu.

* **AFAS - KPN LISA Verbindung:** Die Human Relationship Management (HRM)-Lösung von AFAS ermöglicht die Automatisierung aller HR-Prozesse im Zusammenhang mit sowohl Personal- als auch Gehaltsabrechnungen. Die AFAS - KPN LISA Verbindung stellt sicher, dass alle relevanten Informationen aus AFAS ihren Weg nach KPN LISA finden, ohne dass Sie sich darum kümmern müssen. HelloID fungiert dabei als Vermittler und stellt die korrekte Übersetzung sicher.

HelloID unterstützt über 200 Connectoren und bietet dadurch ein breites Spektrum an Integrationsmöglichkeiten zwischen Ultimo und anderen Quell- und Zielsystemen. Unser Angebot an Connectoren und Integrationen erweitern wir kontinuierlich, sodass Sie mit allen beliebten Systemen integrieren können.