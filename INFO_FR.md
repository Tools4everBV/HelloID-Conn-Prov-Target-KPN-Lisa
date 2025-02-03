Le connecteur cible KPN LISA relie la plateforme KPN LISA à la solution de gestion des identités et des accès (GIA) HelloID de Tools4ever, permettant une connexion fluide avec différents systèmes sources. Cette intégration automatise la gestion des comptes utilisateurs et des autorisations sur les environnements de travail KPN, en s'appuyant sur les données de votre système source. Résultat : moins d'erreurs, des processus plus rapides et une satisfaction utilisateur accrue. 

## Qu’est-ce que KPN LISA ?

KPN LISA est le module d’auto-gestion des environnements de travail de KPN. Conçue pour gérer et sécuriser les comptes utilisateurs, les systèmes et autres ressources sur des réseaux professionnels basés sur Microsoft Azure, cette solution peut fonctionner comme un fournisseur d’identité (IDP) et offrir un point d’accès unique (SSO) à toutes les ressources disponibles au sein de l’infrastructure réseau.

## Pourquoi une intégration KPN LISA est-elle avantageuse ?

Le connecteur HelloID pour KPN LISA permet aux organisations d’optimiser la gestion de leur environnement informatique. En automatisant les tâches essentielles, il réduit les coûts, améliore l’efficacité et élève le niveau global des services IT.

Le connecteur KPN LISA peut se connecter à plusieurs systèmes sources populaires, notamment : 

*	ADP
*	SAP RH

Vous trouverez plus de détails sur ces intégrations plus loin dans cet article.

## Les bénéfices d'HelloID pour KPN LISA

**Une gestion efficace des comptes utilisateurs :** Lorsqu’un nouvel employé est ajouté à votre système RH ou qu’un collaborateur quitte l’entreprise, HelloID détecte automatiquement ces changements dans le système source et les transmet via le connecteur à KPN LISA. Sur cette base, KPN LISA effectue les actions nécessaires, comme l’attribution d’un profil utilisateur ou l’octroi d’une licence Microsoft 365. HelloID s’occupe de la création du compte, tandis que KPN LISA prend en charge les actions associées.

**Une gestion précise des autorisations :** La gestion des autorisations est essentielle pour garantir que les utilisateurs disposent uniquement des accès nécessaires, tout en minimisant les risques pour la sécurité de l’environnement IT. Grâce à l’intégration entre HelloID et KPN LISA, les autorisations sont gérées automatiquement à l’aide de business rules (règles métier). Ces règles pilotent les profils de licences et les groupes de ressources dans KPN LISA, garantissant ainsi une gestion sans erreur.

**Une adaptation flexible des attributs :** L’attribution des droits d’accès peut être automatisée en fonction des attributs des utilisateurs, comme leur fonction ou leur service. HelloID extrait ces informations du système source, vous permettant de définir précisément comment attribuer les droits et les comptes dans KPN LISA. Vous restez ainsi en totale maîtrise du processus. 

## Comment HelloID s’intègre-t-il avec KPN LISA ?

L’intégration de KPN LISA à HelloID est réalisée via un connecteur cible PowerShell. Ce dernier utilise les API REST de KPN LISA pour communiquer avec la plateforme. Pour utiliser cette API, une application doit être enregistrée au sein de l’environnement Microsoft Azure.

| Changement dans le système source |	Procédure dans KPN LISA |
| -------------------------------- | ------------------------ |
| Nouvel employé |	Lorsque qu'un nouvel employé rejoint l'entreprise, il est essentiel qu'il soit opérationnel le plus rapidement possible. Cela nécessite notamment la mise en place des comptes et autorisations adéquats. L'intégration entre KPN LISA et HelloID automatise entièrement ce processus, vous évitant ainsi toute intervention manuelle. HelloID crée automatiquement les comptes nécessaires dans KPN LISA à partir des données de votre système source et attribue les profils d'espace de travail et groupes correspondants. Les autorisations associées sont ensuite gérées et attribuées directement par KPN LISA.|
| Changement de poste |	Les employés peuvent se voir attribuer un nouveau poste au sein de l'organisation, ou bien leurs responsabilités actuelles peuvent évoluer. Ces changements nécessitent souvent des ajustements dans les autorisations associées. Grâce à l'intégration entre HelloID et KPN LISA, ces modifications ne requièrent aucune intervention manuelle. HelloID met automatiquement à jour les profils d'espace de travail et les groupes en fonction des nouvelles données. Les autorisations correspondantes sont ensuite attribuées directement via KPN LISA. Ainsi, vous avez l'assurance que les comptes utilisateurs restent toujours alignés avec les fonctions et responsabilités actuelles de vos employés.|
| Départ d’un employé	| Lorsque qu’un employé quitte l’entreprise, HelloID désactive automatiquement son compte dans KPN LISA et informe les parties concernées. Après un certain délai, le compte est supprimé par HelloID, déclenchant ainsi le processus de nettoyage dans KPN LISA. |


## Intégration de KPN LISA avec des systèmes sources via HelloID

Grâce à HelloID, vous pouvez intégrer divers systèmes avec KPN LISA, y compris plusieurs systèmes sources. Cette interconnexion améliore l'efficacité de la gestion des utilisateurs et des autorisations, tout en garantissant un environnement sécurisé et conforme. Les utilisateurs obtiennent un accès aux systèmes, ressources et données appropriés, en temps voulu. Voici quelques exemples d'intégrations courantes réalisées via HelloID :

*	**ADP – KPN LISA :** Avec l’intégration entre ADP et KPN LISA, HelloID crée automatiquement les comptes utilisateurs nécessaires dans KPN LISA en se basant sur les informations pertinentes issues du système de gestion RH populaire, et attribue les autorisations requises.
*	**SAP RH– KPN LISA :** La solution de gestion des ressources humaines (HRM) de SAP RH permet d’automatiser tous les processus liés à la gestion administrative du personnel et des salaires. L'intégration entre SAP RH et KPN LISA garantit que toutes les données pertinentes issues de SAP RH sont transférées de manière fluide vers KPN LISA. HelloID agit comme un intermédiaire, traduisant automatiquement les informations en configurations adaptées à KPN LISA. 

HelloID propose plus de 200 connecteurs, permettant une vaste gamme d’intégrations entre KPN LISA et d'autres systèmes sources ou cibles. Notre catalogue de connecteurs et d’intégrations est constamment enrichi, garantissant une compatibilité avec les systèmes les plus populaires. Vous pouvez consulter l’ensemble des connecteurs disponibles sur notre site web.