#####################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Create
#
# Version: 1.0.0.0
#####################################################

#region Config
$Config = $Configuration | ConvertFrom-Json
#endregion Config

#region default properties
$p = $Person | ConvertFrom-Json
$m = $Manager | ConvertFrom-Json

$aRef = $null # New-Guid
$mRef = $managerAccountReference | ConvertFrom-Json

$AuditLogs = [Collections.Generic.List[PSCustomObject]]::new()
#endregion default properties

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = @(
    [Net.SecurityProtocolType]::Tls
    [Net.SecurityProtocolType]::Tls11
    [Net.SecurityProtocolType]::Tls12
)

#region functions - Write functions logic here
function Get-LisaAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $TenantId,

        [Parameter(Mandatory = $true)]
        [string]
        $ClientId,

        [Parameter(Mandatory = $true)]
        [string]
        $ClientSecret,

        [Parameter(Mandatory = $true)]
        [string]
        $Scope
    )

    try {
        $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
        $headers.Add("Content-Type", "application/x-www-form-urlencoded")

        $body = @{
            grant_type    = "client_credentials"
            client_id     = $ClientId
            client_secret = $ClientSecret
            scope         = $Scope
        }

        $splatRestMethodParameters = @{
            Uri     = "https://login.microsoftonline.com/$($TenantId)/oauth2/v2.0/token/"
            Method  = 'POST'
            Headers = $headers
            Body    = $body
        }
        Invoke-RestMethod @splatRestMethodParameters
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}


function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )

    process {
        $HttpErrorObj = @{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            InvocationInfo        = $ErrorObject.InvocationInfo.MyCommand
            TargetObject          = $ErrorObject.TargetObject.RequestUri
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $HttpErrorObj['ErrorMessage'] = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $reader = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream())
            $HttpErrorObj['ErrorMessage'] = $reader.ReadToEnd()
        }
        Write-Output "'$($HttpErrorObj.ErrorMessage)', TargetObject: '$($HttpErrorObj.TargetObject), InvocationCommand: '$($HttpErrorObj.InvocationInfo)"
    }
}
#endregion functions

# Build the Final Account object
$Account = @{
    givenName                = $p.Name.NickName
    surName                  = $p.Name.FamilyName
    userPrincipalName        = "$($p.ExternalId).onmicrosoft.com"
    displayName              = $p.DisplayName
    changePasswordNextSignIn = $false
    usageLocation            = 'NL'
}

$Success = $False

# Start Script
try {
    Write-Verbose 'Getting accessToken'

    $splatGetTokenParams = @{
        TenantId     = $Config.TenantId
        ClientId     = $Config.ClientId
        ClientSecret = $Config.ClientSecret
        Scope        = $Config.Scope
    }
    $accessToken = (Get-LisaAccessToken @splatGetTokenParams).access_token

    $authorizationHeaders = [System.Collections.Generic.Dictionary[[String],[String]]]::new()
    $authorizationHeaders.Add("Authorization", "Bearer $accessToken")
    $authorizationHeaders.Add("Content-Type", "application/json")
    $authorizationHeaders.Add("Mwp-Api-Version", "1.0")

    # Create user
    Write-Verbose "Creating KPN Lisa account for '$($p.DisplayName)'"

    $splatParams = @{
        Uri     = "$($Config.BaseUrl)/Users?filter=startswith(userprincipalname,'$($account.userPrincipalName)')"
        Method  = 'get'
        Headers = $authorizationHeaders
    }
    $userResponse = Invoke-RestMethod @splatParams
    if ($userResponse.count -eq 0) {
        $splatParams = @{
            Uri     = "$($Config.BaseUrl)/Users"
            Method  = 'POST'
            Body    = ($account | ConvertTo-Json)
            Headers = $authorizationHeaders
        }

        if (-not($dryRun -eq $true)) {
            $userResponse = Invoke-RestMethod @splatParams
            $aRef = $($userResponse.objectId)

            $AuditLogs.Add([PSCustomObject]@{
                    Action  = "CreateAccount" # Optionally specify a different action for this audit log
                    Message = "Created account for '$($p.DisplayName)'. Id: $($aRef)"
                    IsError = $False
                })
        }

        #Set Default WorkSpaceProfile
        $workSpaceProfileGuid = "500708ea-b69f-4f6c-83fc-dd5f382c308b" #WorkspaceProfile  "friendlyDisplayName": "Ontzorgd"

        $splatParams = @{
            Uri     = "$($Config.BaseUrl)/Users/$aRef/WorkspaceProfiles"
            Method  = 'PUT'
            Headers = $authorizationHeaders
            body    = ($workSpaceProfileGuid | ConvertTo-Json)
        }

        if (-not($dryRun -eq $true)) {
            $null = Invoke-RestMethod @splatParams #If 200 it returns a Empty String
        }

        Write-Verbose "Added Workspace profile [Ontzorgd]" -Verbose

    }
    elseif ( $userResponse.count -eq 1) {
        $userResponse = $userResponse.value
        $aRef = $($userResponse.id)

        $AuditLogs.Add([PSCustomObject]@{
                Action  = "CreateAccount" # Optionally specify a different action for this audit log
                Message = "Correlated to account with id $($aRef)"
                IsError = $False
            })
    }

    if ($userResponse) {
        # Set the manager
        if ($m) {
            $splatParams = @{
                Uri     = "$($Config.BaseUrl)/Users?filter=startswith(userprincipalname,'$($m.ExternalId)')"
                Method  = 'GET'
                Headers = $authorizationHeaders
            }
            $managerResponse = Invoke-RestMethod @splatParams

            if ($managerResponse.count -eq 1) {
                $splatParams = @{
                    Uri     = "$($Config.BaseUrl)/Users/$($aRef)/Manager"
                    Method  = 'Put'
                    Body    = ($managerResponse.Value.id | ConvertTo-Json)
                    Headers = $authorizationHeaders
                }

                if (-not($dryRun -eq $true)) {
                    $null = Invoke-RestMethod @splatParams
                }

                Write-Verbose "Added Manager $($managerResponse.Value.displayName) to '$($p.DisplayName)'" -Verbose
            }
            else {
                throw  "Manager not Found '$($m.ExternalId)'"
            }
        }
        $Success = $true
    }
}
catch {
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorMessage = Resolve-HTTPError -Error $ex
    }
    else {
        $errorMessage = $ex.Exception.Message
    }

    $AuditLogs.Add([PSCustomObject]@{
            Action  = "CreateAccount" # Optionally specify a different action for this audit log
            Message = "Account for '$($p.DisplayName)' not created. Error: $errorMessage"
            IsError = $True
        })
}


$result = [PSCustomObject]@{
    Success          = $Success
    AccountReference = $aRef
    AuditLogs        = $AuditLogs
    Account          = $account

    # Optionally return data for use in other systems
    # ExportData = [PSCustomObject]@{
    #     DisplayName = $Account.DisplayName
    #     UserName    = $Account.UserName
    #     ExternalId  = $aRef
    # }
}

Write-Output $result | ConvertTo-Json -Depth 10
