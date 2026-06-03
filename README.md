# HelloID-Conn-Prov-Target-KPN-Lisa

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-KPN-Lisa/refs/heads/main/Logo.png?raw=true" alt="KPN Lisa Logo">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-KPN-Lisa](#helloid-conn-prov-target-kpn-lisa)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Requirements](#requirements)
    - [Create an Application in Entra ID](#create-an-application-in-entra-id)
    - [Set Up Permissions for KPN MWP API](#set-up-permissions-for-kpn-mwp-api)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
    - [Workspace Profile](#workspace-profile)
    - [Persona](#persona)
    - [Manager Field in Field Mapping](#manager-field-in-field-mapping)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-KPN-Lisa_ is a target connector. KPN Lisa provides a set of REST APIs that allow you to programmatically interact with its data.

## Supported features

The following features are available:

| Feature                                   | Supported | Actions                                 | Remarks                      |
| ----------------------------------------- | --------- | --------------------------------------- | ---------------------------- |
| **Account Lifecycle**                     | ✅         | Create, Update, Enable, Disable, Delete |                              |
| **Permissions**                           | ✅         | Retrieve, Grant, Revoke                 | Only `Groups` and `Personas` |
| **Resources**                             | ❌         | -                                       |                              |
| **Entitlement Import: Accounts**          | ✅         | -                                       |                              |
| **Entitlement Import: Permissions**       | ✅         | -                                       |                              |
| **Governance Reconciliation Resolutions** | ✅         | -                                       |                              |

## Getting started

### HelloID Icon URL

URL of the icon used for the HelloID Provisioning target system.

```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-KPN-Lisa/refs/heads/main/Logo.png
```

### Requirements

- **MWP API Credentials**: Refer to the KPN MWP API documentation for detailed instructions: [MWP API documentation](https://mwpapi.kpnwerkplek.com/index.html).
  - Create an **App Registration** in Microsoft Entra ID.
  - Create access credentials for your app:
    - Create a **client secret** for your app.
  - Send the **Application (client) ID** to your KPN Modern Workplace contact, they will configure the required permissions.

### Create an Application in Entra ID

To use the HelloID-KPN Lisa connector, you must first create a **Microsoft Entra ID Application**.

1. **Navigate to App Registrations**:
   - Go to the Microsoft Entra ID Portal.
   - Navigate to **Microsoft Entra ID** > **App registrations**.
   - Click on **New registration**.

2. **Register the Application**:
   - **Name**: Enter a name for your application (e.g., "HelloID PowerShell - KPN Lisa").
   - **Supported Account Types**: Choose "Accounts in this organizational directory only".
   - **Redirect URI**: Set the platform to **Web** and use a redirect URI (e.g., `http://localhost`).

3. **Complete the Registration**:
   - Click the **Register** button to create your new application.

Refer to [Microsoft's Quickstart guide](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app?tabs=certificate) for more details.

### Set Up Permissions for KPN MWP API

1. **Contact KPN**:  
   Request KPN to whitelist your **TenantId** and **AppId** for access to the MWP API.

2. **Verify Configuration**:  
   Once whitelisted, verify that your app can interact with the MWP API by ensuring users and permissions are returned correctly.

For more information, see the [MWP API documentation](https://mwpapi.kpnwerkplek.com/index.html).

### Connection settings

The following settings are required to connect to the KPN MWP API:

| Setting                                                           | Description                                                                                                                                                                                                                                                                                                                               | Mandatory |
| ----------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| **Entra ID App Registration Directory (tenant) ID**               | The ID to the Tenant in Microsoft Entra ID.                                                                                                                                                                                                                                                                                               | Yes       |
| **Entra ID App Registration Application (client) ID**             | The ID to the App Registration in Microsoft Entra ID.                                                                                                                                                                                                                                                                                     | Yes       |
| **Entra ID App Registration Client Secret**                       | The Client Secret to the App Registration in Microsoft Entra ID.                                                                                                                                                                                                                                                                          | Yes       |
| **KPN MWP Scope**                                                 | The scope used when creating the access token. Choose from the following based on your environment: <br> - **Development:** `https://kpnwp.onmicrosoft.com/kpnmwpdmwpapi/.default` <br> - **Test:** `https://kpnwp.onmicrosoft.com/kpnmwptmwpapi/.default` <br> - **Production:** `https://kpnwp.onmicrosoft.com/kpnmwppmwpapi/.default`. | Yes       |
| **MWP API BaseUrl**                                               | The URL of the MWP API service.                                                                                                                                                                                                                                                                                                           | Yes       |
| **Set manager when an account is created**                        | When toggled, this connector will calculate and set the manager upon creating an account.                                                                                                                                                                                                                                                 | No        |
| **Update manager when the account update operation is performed** | When toggled, this connector will calculate and set the manager upon updating an account.                                                                                                                                                                                                                                                 | No        |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within KPN Lisa to a person in HelloID.

| Setting                       | Value                             |
| ----------------------------- | --------------------------------- |
| **Enable correlation**        | `True`                            |
| **Person correlation field**  | `PersonContext.Person.ExternalId` |
| **Account correlation field** | `employeeId`                      |

> Ensure the **Account Correlation Field** is supported by the MWP API's capabilities. Verify that your setup is supported by the [GET /api/users](https://mwpapi.kpnwerkplek.com/index.html).

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Account Reference

The account reference is populated with the `id` property from KPN Lisa.

## Remarks

### Workspace Profile

- In KPN Lisa, a user can only have one WorkspaceProfile, so be careful not to add multiple profiles to a user. The revoke action will remove whatever workspaceProfile is active at the moment. This can result in unwanted behavior.

### Persona

- A user can have only one Persona in KPN Lisa. Assigning more than one will return an error. Ensure your Business Rules assign only a single Persona per user.

### Manager Field in Field Mapping

- The `managerId` field is optional and represents the manager's ID for the user. This field is read-only.
- **Note:** The `managerId` field uses a "None" mapping because the value is calculated within the scripts. The manager must exist in KPN Lisa and be managed by HelloID. Assign the **Account entitlement** to the manager before setting this field.

## Development resources

### API endpoints

The following endpoints are used by the connector:

| Endpoint                                                     | HTTP Method      | Description                            |
| ------------------------------------------------------------ | ---------------- | -------------------------------------- |
| `/api/users`                                                 | GET              | Get users                              |
| `/api/users/{identifier}`                                    | GET              | Get a specific user                    |
| `/api/users`                                                 | POST             | Create user                            |
| `/api/users/{identifier}/bulk`                               | PATCH            | Update user properties in bulk         |
| `/api/users/{identifier}`                                    | DELETE           | Delete user                            |
| `/api/users/{identifier}/manager`                            | GET, PUT, DELETE | Get, update, or delete manager of user |
| `/api/groups`                                                | GET              | List groups                            |
| `/api/users/{identifier}/groups`                             | POST             | Add member to group                    |
| `/api/users/{identifier}/groups/{groupidentifier}`           | DELETE           | Remove member from group               |
| `/api/licenses`                                              | GET              | List licenses                          |
| `/api/users/{identifier}/licenses`                           | POST             | Add license to user                    |
| `/api/users/{identifier}/licenses/{skuId}`                   | DELETE           | Remove license from user               |
| `/api/teams`                                                 | GET              | List teams                             |
| `/api/users/{identifier}/teams`                              | POST             | Add team to user                       |
| `/api/users/{identifier}/teams/{memberId}`                   | DELETE           | Remove team from user                  |
| `/api/lisaroles`                                             | GET              | List lisa roles                        |
| `/api/users/{identifier}/lisaroles`                          | POST             | Add lisa role to user                  |
| `/api/users/{identifier}/lisaroles/{roleId}`                 | DELETE           | Remove lisa role from user             |
| `/api/licenseprofiles`                                       | GET              | List license profiles                  |
| `/api/users/{identifier}/licenseprofiles`                    | POST             | Add license profile to user            |
| `/api/users/{identifier}/licenseprofiles/{licenseProfileId}` | DELETE           | Remove license profile from user       |
| `/api/authorizationprofiles`                                 | GET              | List authorization profiles            |
| `/api/users/{identifier}/authorizationprofiles`              | POST             | Add authorization profile to user      |
| `/api/AuthorizationProfiles/{identifier}/members/{memberId}` | DELETE           | Remove authorization profile from user |
| `/api/workspaceprofiles`                                     | GET              | List workspace profiles                |
| `/api/users/{identifier}/workspaceprofiles`                  | POST             | Add workspace profile to user          |
| `/api/users/{identifier}/workspaceprofiles`                  | DELETE           | Remove workspace profile from user     |
| `/api/personas`                                              | GET              | List personas                          |
| `/api/Personas/{identifier}/members`                         | POST             | Add persona to user                    |
| `/api/Personas/{identifier}/members/{memberId}`              | DELETE           | Remove persona from user               |
| `/api/users/{identifier}/authentication`                     | GET              | List authentication methods for user   |
| `/api/users/{identifier}/authentication/phone`               | POST             | Add phone authentication method        |
| `/api/users/{identifier}/authentication/phone/{id}`          | DELETE           | Remove phone authentication method     |
| `/api/users/{identifier}/authentication/email`               | POST             | Add email authentication method        |
| `/api/users/{identifier}/authentication/email/{id}`          | DELETE           | Remove email authentication method     |

### API documentation

For more information, see the [MWP API documentation](https://mwpapi.kpnwerkplek.com/index.html).

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: [https://docs.helloid.com/](https://docs.helloid.com/)
