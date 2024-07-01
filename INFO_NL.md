## KPN LISA Target Connector

De KPN LISA target connector koppelt KPN LISA via de Identity & Access Management (IAM)-oplossing HelloID van Tools4ever aan diverse bronsystemen. Prettig, want zo automatiseer je het beheer van gebruikersaccounts en autorisaties in KPN-werkplekken. Gegevens uit je bronsysteem zijn daarbij altijd leidend, wat fouten voorkomt. Je bespaart tijd, ondersteunt je organisatie optimaal en verhoogt de gebruikerstevredenheid. 

## Wat is KPN LISA?

KPN LISA is de naam van de KPN Werkplek Self Service-module, gericht op het beheer van alle vormen van KPN-werkplekken. De module ondersteunt IT-beheerders bij het managen en beveiligen van gebruikersaccounts, systemen en andere middelen op Microsoft Azure-gebaseerde bedrijfsnetwerken. KPN LISA kan dienstdoen als identity provider (IDP) en een single point of access vormen voor middelen die via het bedrijfsnetwerk beschikbaar zijn.

## Waarom is een KPN LISA koppeling handig?

Met de HelloID KPN LISA connector kunnen organisaties hun IT-omgeving efficiënter en effectiever beheren. De connector bespaart zo tijd en kosten, en tilt tegelijkertijd de algehele dienstverlening naar een hoger niveau. 

De KPN LISA connector maakt een koppeling met diverse populaire bronsystemen mogelijk. Denk daarbij aan: 

* Visma Raet
* AFAS

Verdere details over de koppeling met deze bronsystemen vind je verderop in het artikel.

## HelloID voor KPN LISA helpt je met

**Gebruikersaccounts adequaat beheren:** Voeg je een nieuwe medewerker toe aan je HR-systeem, of verwijder je juist een medewerker? HelloID detecteert deze wijziging in je bronsysteem automatisch en zet dit via de connector door naar KPN LISA. Op basis van door HelloID vastgestelde werkplekprofielen voert KPN LISA vervolgens acties uit. Zo voorziet KPN LISA bijvoorbeeld de medewerker van een gebruikersprofiel en een M365-licentie. Belangrijk om op te merken is dat HelloID de actie uitvoert op het account, en KPN LISA de vervolgacties voor rekening neemt. 

**Foutloos beheer van autorisaties:** Met behulp van autorisaties bepaal je tot welke applicaties, systemen en bronnen een gebruiker toegang heeft. Je wilt autorisaties dan ook foutloos beheren om zeker te stellen dat gebruikers over de juiste toegang beschikken, en anderzijds je omgeving zo veilig mogelijk te houden. Dankzij de koppeling tussen HelloID en KPN LISA heb je hiernaar geen omkijken. HelloID beheert via business rules de lidmaatschappijen van licentieprofielen en resourcegroepen in KPN LISA. 

**Attributen aanpassen:** Met behulp van groepen bepaal je in één keer de autorisaties voor een groep gebruikers. Welke groepslidmaatschappen een gebruiker krijgt toegewezen, is onder meer afhankelijk van diens functie en/of afdeling. Het identificeren hiervan kan je in belangrijke mate automatiseren. Dit proces werkt met behulp van attributen, die HelloID ophaalt uit je bronsysteem. Je bepaalt zelf op basis van welk attribuut je welke accounts en rechten wilt toekennen in KPN LISA. Je staat dus altijd zelf aan de knoppen. 

## Hoe HelloID integreert met KPN LISA

Met behulp van de KPN LISA target connector koppel je KPN LISA aan HelloID. Je maakt hierbij gebruik van een HelloID powershell target connector. HelloID communiceert met behulp van deze connector via powershell met de REST API webservices van KPN LISA. Het gebruik van deze API vereist een app-registratie in de Microsoft Azure-tenant.

| Wijziging in KPN LISA                       | Procedure in doelsystemen |
| ----------------------------------------- | --------------------------|
| **Nieuwe medewerker** |	Indien een nieuwe medewerker in dienst treedt wil je dat deze gebruiker zo snel mogelijk productief is. Dit vraagt onder meer om de juiste accounts en autorisaties. De koppeling van KPN LISA en HelloID automatiseert dit proces, zodat jij hiernaar geen omkijken hebt. Zo maakt HelloID op basis van je bronsysteem automatisch de benodigde accounts aan in KPN LISA en kent workspace profiles en groepen toe. De bijbehorende autorisaties worden via KPN Lisa toegewzen. |
| **Andere functie medewerker** |	Medewerkers kunnen binnen een organisatie een nieuwe functie toegewezen krijgen. Ook kan een bestaande functie op de schop gaan. Beide veranderingen vragen om andere autorisaties. Dankzij de koppeling tussen HelloID en KPN LISA vereist dit geen handmatige handelingen en past HelloID automatisch de workspace profiles en groepen aan. De bijbehorende autorisaties worden via KPN Lisa toegewezen. Zo weet je zeker dat gebruikersaccounts altijd in lijn zijn met de actuele functies binnen je organisatie. 
| **Medewerker treedt uit dienst** | Indien een medewerker uit dienst treedt deactiveert HelloID automatisch het gebruikersaccount in KPN LISA. Ook informeert de IAM-oplossing alle betrokken medewerkers. Na verloop van tijd verwijdert HelloID het KPN LISA-account automatisch, waardoor het clearproces in KPN Lisa wordt gestart.| 


## KPN LISA via HelloID koppelen met bronsystemen

Met behulp van HelloID kan je diverse systemen met KPN LISA integreren, waaronder allerlei bronsystemen. Prettig, want zo vergroot je onder meer de efficiëntie bij het beheer van gebruikers en autorisaties. Je realiseert een veilige en compliant omgeving, waarin gebruikers altijd over toegang tot de juiste systemen, middelen en gegevens beschikken. Enkele voorbeelden van veelvoorkomende integraties via HelloID zijn:

* Visma Raet - KPN LISA koppeling: Met behulp van de Visma Raet - KPN LISA koppeling maakt de IAM-oplossing op basis van alle relevante informatie uit het populaire HR-systeem automatisch de juiste gebruikersaccounts aan in KPN LISA en kent de benodigde autorisaties toe.

* AFAS - KPN LISA koppeling: De Human Relationship Management (HRM)-oplossing van AFAS stelt je in staat tot het automatiseren van alle HR-processen gerelateerd aan zowel personeels- als salarisadministratie. De AFAS - KPN LISA koppeling zorgt dat alle relevante informatie uit AFAS zijn weg vindt naar AFAS, zonder dat jij hiernaar omkijken hebt. HelloID fungeert daarbij als tussenpersoon en maakt de juiste vertaalslag. 

HelloID ondersteunt ruim 200 connectoren, waarmee we een breed scala aan integratiemogelijkheden bieden tussen Ultimo en andere bron- en doelsystemen. Ons aanbod aan connectoren en integraties continu breiden we continu uit, waardoor je met alle populaire systemen kunt integreren.

