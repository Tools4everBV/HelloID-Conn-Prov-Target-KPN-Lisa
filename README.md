# HelloID-Conn-Prov-Target-KPN-Lisa

> [!WARNING]
> This script is for the new powershell connector. Make sure to use the mapping and correlation keys like mentioned in this readme. For more information, please read our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html)

> [!IMPORTANT]
> This repository contains only the connector and configuration code. The implementer is responsible for acquiring connection details such as the username, password, certificate, etc. You may also need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-KPN-Lisa/blob/main/Logo.png?raw=true" alt="KPN Lisa Logo">
</p>

## Table of Contents

- [HelloID-Conn-Prov-Target-KPN-Lisa](#helloid-conn-prov-target-kpn-lisa)
  - [Table of Contents](#table-of-contents)
  - [Requirements](#requirements)
  - [Remarks](#remarks)
    - [Workspace Profile](#workspace-profile)
    - [Manager Field in Field Mapping](#manager-field-in-field-mapping)
  - [Introduction](#introduction)
    - [Actions](#actions)
  - [Getting Started](#getting-started)
    - [Create a Provider in Zenya](#create-a-provider-in-zenya)
    - [Set Up Permissions for KPN MWP API](#set-up-permissions-for-kpn-mwp-api)
    - [Provisioning PowerShell V2 connector](#provisioning-powershell-v2-connector)
      - [Correlation Configuration](#correlation-configuration)
      - [Field mapping](#field-mapping)
    - [Connection Settings](#connection-settings)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Requirements

1. **MWP Api Credentials**: Refer to the KPN MWP API documentation for detailed instructions: [MWP Api documentation](https://mwpapi.kpnwerkplek.com/index.html).
   - Create an **App Registration** in Microsoft Entra ID.
   - Create access credentials for your app:
     - Create a **client secret** for your app.
   - Send the **Application (client) ID** to your KPN Modern Workplace contact, they will configure the required permissions.


## Remarks

### Workspace Profile

- In KPN Lisa, a user can only have one WorkspaceProfile, so be careful not to add multiple profiles to a user. The revoke action will remove whatever workspaceProfile is active at the moment. This can result in unwanted behavior.


### Manager Field in Field Mapping

- The `managerId` field is optional and represents the manager's ID for the user. This field is read-only.

- **Note:** The `managerId` field uses a "None" mapping because the value is calculated within the scripts. We can only assign a manager who exists in KPN Lisa and was created by HelloID. Before assigning a manager, HelloID must first grant the Account entitlement to the manager.

## Introduction

_HelloID-Conn-Prov-Target-KPN-Lisa_ is a _target_ connector. _KPN_ provides a set of REST API's that allow you to programmatically interact with its data. The KPN Lisa connector uses the API endpoints listed in the table below.

| Endpoint                                                                                                | Description                                     |
| ------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| [/api/users](https://mwpapi.kpnwerkplek.com/index.html)                                                 | Get users (GET)                                 |
| [/api/users/{identifier}](https://mwpapi.kpnwerkplek.com/index.html)                                    | Get a specific user (GET)                       |
| [/api/users](https://mwpapi.kpnwerkplek.com/index.html)                                                 | Create user (POST)                              |
| [/api/users/{identifier}/bulk](https://mwpapi.kpnwerkplek.com/index.html)                               | Update user properties in bulk (PATCH)          |
| [/api/users/{identifier}](https://mwpapi.kpnwerkplek.com/index.html)                                    | Delete user (DELETE)                            |
| [/api/users/{identifier}/manager](https://mwpapi.kpnwerkplek.com/index.html)                            | Get manager of user (GET)                       |
| [/api/users/{identifier}/manager](https://mwpapi.kpnwerkplek.com/index.html)                            | Update manager of user (PUT)                    |
| [/api/users/{identifier}/manager](https://mwpapi.kpnwerkplek.com/index.html)                            | Delete manager of user (DELETE)                 |
| [/api/groups](https://mwpapi.kpnwerkplek.com/index.html)                                                | List groups (GET)                               |
| [/api/users/{identifier}/groups](https://mwpapi.kpnwerkplek.com/index.html)                             | Add member (POST)                               |
| [/api/users/{identifier}/groups/{groupidentifier}](https://mwpapi.kpnwerkplek.com/index.html)           | Remove member (DELETE)                          |
| [/api/licenses](https://mwpapi.kpnwerkplek.com/index.html)                                              | List licenses (GET)                             |
| [/api/users/{identifier}/licenses](https://mwpapi.kpnwerkplek.com/index.html)                           | Add license to user (POST)                      |
| [//api/users/{identifier}/licenses/{skuId}](https://mwpapi.kpnwerkplek.com/index.html)                  | Remove license from user (DELETE)               |
| [/api/teams](https://mwpapi.kpnwerkplek.com/index.html)                                                 | List teams (GET)                                |
| [/api/users/{identifier}/teams](https://mwpapi.kpnwerkplek.com/index.html)                              | Add team to user (POST)                         |
| [/api/users/{identifier}/teams/{memberId}](https://mwpapi.kpnwerkplek.com/index.html)                   | Remove team from user (DELETE)                  |
| [/api/lisaroles](https://mwpapi.kpnwerkplek.com/index.html)                                             | List lisa roles (GET)                           |
| [/api/users/{identifier}/lisaroles](https://mwpapi.kpnwerkplek.com/index.html)                          | Add lisa role to user (POST)                    |
| [/api/users/{identifier}/lisaroles{roleId}](https://mwpapi.kpnwerkplek.com/index.html)                  | Remove lisa role from user (DELETE)             |
| [/api/licenseprofiles](https://mwpapi.kpnwerkplek.com/index.html)                                       | List license profiles (GET)                     |
| [/api/users/{identifier}/licenseprofiles](https://mwpapi.kpnwerkplek.com/index.html)                    | Add license profile to user (POST)              |
| [/api/users/{identifier}/licenseprofiles/{licenseProfileId}](https://mwpapi.kpnwerkplek.com/index.html) | Remove license profile from user (DELETE)       |
| [/api/authorizationprofiles](https://mwpapi.kpnwerkplek.com/index.html)                                 | List authorization profiles (GET)               |
| [/api/users/{identifier}/authorizationprofiles](https://mwpapi.kpnwerkplek.com/index.html)              | Add authorization profile to user (POST)        |
| [/api/AuthorizationProfiles/{identifier}/members/{memberId}](https://mwpapi.kpnwerkplek.com/index.html) | Remove authorization profile from user (DELETE) |
| [/api/workspaceprofiles](https://mwpapi.kpnwerkplek.com/index.html)                                     | List workspace profiles (GET)                   |
| [/api/users/{identifier}/workspaceprofiles](https://mwpapi.kpnwerkplek.com/index.html)                  | Add workspace profile to user (POST)            |
| [/api/users/{identifier}/workspaceprofiles](https://mwpapi.kpnwerkplek.com/index.html)                  | Remove workspace profile from user (DELETE)     |


### Actions

| Action                                         | Description                                          | Comment                                                |
| ---------------------------------------------- | ---------------------------------------------------- | ------------------------------------------------------ |
| `create.ps1`                                   | Create (or update) and correlate a user account      |                                                        |
| `enable.ps1`                                   | Enable a user account                                |                                                        |
| `update.ps1`                                   | Update a user account                                |                                                        |
| `disable.ps1`                                  | Disable a user account                               |                                                        |
| `delete.ps1`                                   | Delete a user account                                | Be cautious; deleted users cannot be restored.         |
| `groups - permissions.ps1`                     | Retrieve all groups and provide them as entitlements |                                                        |
| `groups - grantPermission.ps1`                 | Add a group to a user account                        |                                                        |
| `groups - revokePermission.ps1`                | Remove a group from a user account                   |                                                        |
| `licenses - grantPermission.ps1`               | Assign a license to a user account                   |                                                        |
| `licenses - revokePermission.ps1`              | Remove a license from a user account                 |                                                        |
| `teams - grantPermission.ps1`                  | Add a user to a team                                 |                                                        |
| `teams - revokePermission.ps1`                 | Remove a user from a team                            |                                                        |
| `lisaroles - grantPermission.ps1`              | Assign a Lisa role to a user                         |                                                        |
| `lisaroles - revokePermission.ps1`             | Remove a Lisa role from a user                       |                                                        |
| `licenseprofiles - grantPermission.ps1`        | Assign a license profile to a user                   |                                                        |
| `licenseprofiles - revokePermission.ps1`       | Remove a license profile from a user                 |                                                        |
| `authorizationprofiles - grantPermission.ps1`  | Add an authorization profile to a user account       |                                                        |
| `authorizationprofiles - revokePermission.ps1` | Remove an authorization profile from a user          |                                                        |
| `workspaceprofiles - grantPermission.ps1`      | Assign a workspace profile to a user                 |                                                        |
| `workspaceprofiles - revokePermission.ps1`     | Remove a workspace profile from a user account       | Be cautious; this removes the active WorkspaceProfile. |


## Getting Started

### Create a Provider in Zenya

To start using the HelloID-KPNLisa connector, you first need to create a new **Microsoft Entra ID Application**. This application will be used to connect to the API and manage permissions.

Follow these steps:

1. **Navigate to App Registrations**:
   - Go to the Microsoft Entra ID Portal.
   - Navigate to **Microsoft Entra ID** > **App registrations**.
   - Click on **New registration**.

2. **Register the Application**:
   - **Name**: Enter a name for your application (e.g., "HelloID PowerShell").
   - **Supported Account Types**: Choose who can use this application (e.g., "Accounts in this organizational directory only").
   - **Redirect URI**: Choose the platform as `Web` and enter a redirect URI (e.g., `http://localhost`).

3. **Complete the Registration**:
   - Click the **Register** button to create your new application.

For detailed steps, refer to the official Microsoft guide: [Quickstart: Register an app in the Microsoft identity platform](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app?tabs=certificate).

### Set Up Permissions for KPN MWP API

By default, the Microsoft Entra ID Application is unable to communicate with the KPN MWP API for Lisa. To enable this, follow these steps:

1. **Contact KPN**:
   - Reach out to KPN to request whitelisting of your **TenantId** and **AppId** for the MWP API.

2. **Verify Configuration**:
   - Once KPN completes the whitelisting, ensure the application is able to interact with the MWP API. Verify that users and permissions are returned as expected.

For more detailed information, refer to [MWP Api documentation](https://mwpapi.kpnwerkplek.com/index.html).

### Provisioning PowerShell V2 connector

#### Correlation Configuration
The correlation configuration specifies which properties are used to match accounts in KPN Lia with users in HelloID.

To properly set up the correlation:

1. Open the `Correlation` tab.

2. Specify the following configuration:

    | Setting                       | Value        |
    | ----------------------------- | ------------ |
    | **Person Correlation Field**  | `ExternalId` |
    | **Account Correlation Field** | `employeeId` |

> Ensure the **Account Correlation Field** is supported by the MWP API's capabilities. Verify that your setup is supported by the [GET /api/users](https://mwpapi.kpnwerkplek.com/index.html).

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

#### Field mapping
The field mapping can be imported by using the _fieldMapping.json_ file.

### Connection Settings

The following settings are required to connect to the KPN MWP API:

| Setting                                                           | Description                                                                                                                                                                                                                                                                                                                      | Mandatory |
| ----------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| **Entra ID App Registration Directory (tenant) ID**               | The ID to the Tenant in Microsoft Entra ID.                                                                                                                                                                                                                                                                                      | Yes       |
| **Entra ID App Registration Application (client) ID**             | The ID to the App Registration in Microsoft Entra ID .                                                                                                                                                                                                                                                                           | Yes       |
| **Entra ID App Registration Client Secret**                       | The Client Secret to the App Registration in Microsoft Entra ID.                                                                                                                                                                                                                                                                 | Yes       |
| **KPN MWP Scope**                                                 | The scope to send when creating the access token. https://kpnwp.onmicrosoft.com/kpnmwpdmwpapi/.default for KPN Modern Workplace - Development. https://kpnwp.onmicrosoft.com/kpnmwptmwpapi/.default for KPN Modern Workplace - Test. https://kpnwp.onmicrosoft.com/kpnmwppmwpapi/.default for KPN Modern Workplace - Production. | Yes       |
| **MWP Api BaseUrl**                                               | The URL of the MWP API service.                                                                                                                                                                                                                                                                                                  | Yes       |
| **Set manager when an account is created**                        | When toggled, this connector will calculate and set the manager upon creating an account.                                                                                                                                                                                                                                        | No        |
| **Update manager when the account update operation is performed** | When toggled, this connector will calculate and set the manager upon updating an account.                                                                                                                                                                                                                                        | No        |
| **Toggle debug logging**                                          | Displays debug logging when toggled. **Switch off in production**                                                                                                                                                                                                                                                                | No        |

## Getting help
> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_.

## HelloID docs
The official HelloID documentation can be found at: https://docs.helloid.com/
