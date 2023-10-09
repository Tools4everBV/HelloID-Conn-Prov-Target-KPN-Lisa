#####################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Update
#
# Version: 1.0.0.0
#####################################################

#region Config
$Config = $Configuration | ConvertFrom-Json

# - Add your configuration variables here -
$Uri = $Config.Uri
#endregion Config

#region default properties
$p = $person | ConvertFrom-Json
$m = $manager | ConvertFrom-Json
$pp = $previousPerson | ConvertFrom-Json
$pd = $personDifferences | ConvertFrom-Json

$aRef = $accountReference | ConvertFrom-Json
$mRef = $managerAccountReference | ConvertFrom-Json

$auditLogs = [Collections.Generic.List[PSCustomObject]]::new()
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
            Uri     = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token/"
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
    userPrincipalName        = "$($p.ExternalId)@impegno.onmicrosoft.com"
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

    Write-Verbose "Updating KPN Lisa account for '$($p.DisplayName)'"

    $splatParams = @{
        Uri     = "$($Config.BaseUrl)/Users/$aRef"
        Method  = 'PATCH'
        Headers = $authorizationHeaders
    }

    # TODO:: Create smaller dryrun scope
    if (-not($dryRun -eq $true)) {
        if ( ($pd.Name.GivenName) -and ($pd.Name.GivenName.Change -eq "Updated") ) {
            $splatParams['Body'] = [PSCustomObject]@{
                propertyName = "givenName"
                value        = $($pd.Name.GivenName.New)
            } | ConvertTo-Json
            $null = Invoke-RestMethod @splatParams
            $success = $true

            $AuditLogs.Add([PSCustomObject]@{
                    Action  = "UpdateAccount" # Optionally specify a different action for this audit log
                    Message = "Account for '$($p.DisplayName)' Updated. ObjectId: '$($userResponse.objectId)'"
                    IsError = $false
                })
        }
        if ( ($pd.Name.FamilyName) -and ($pd.Name.FamilyName.Change -eq "Updated") ) {
            $splatParams['Body'] = [PSCustomObject]@{
                propertyName = "surName"
                value        = $($pd.Name.FamilyName.New)
            } | ConvertTo-Json
            $null = Invoke-RestMethod @splatParams
            $success = $true

            $AuditLogs.Add([PSCustomObject]@{
                    Action  = "UpdateAccount" # Optionally specify a different action for this audit log
                    Message = "Account for '$($p.DisplayName)' Updated. ObjectId: '$($userResponse.objectId)'"
                    IsError = $false
                })
        }
        if ($null -eq $m) {
            $splatDeleteManagerParams = @{
                Uri     = "$($Config.BaseUrl)/Users/$aRef/manager"
                Method  = 'DELETE'
                Headers = $authorizationHeaders
            }
            $null = Invoke-RestMethod @splatDeleteManagerParams
            $success = $true

            $AuditLogs.Add([PSCustomObject]@{
                    Action  = "UpdateAccount" # Optionally specify a different action for this audit log
                    Message = "Manager for '$($p.DisplayName)' deleted. ObjectId: '$($userResponse.objectId)'"
                    IsError = $false
                })
        }
        elseif ( ($pd.PrimaryManager.PersonId) -and ($pd.PrimaryManager.PersonId.Change -eq "Updated") ) {
            $splatUpdateManagerParams = @{
                Uri     = "$($Config.BaseUrl)/Users/$($objectId)/Manager"
                Method  = 'PUT'
                Body    = ($pd.PrimaryManager.PersonId.New | ConvertTo-Json)
                Headers = $authorizationHeaders
            }
            $null = Invoke-RestMethod @splatUpdateManagerParams
            $success = $true

            $AuditLogs.Add([PSCustomObject]@{
                    Action  = "UpdateAccount" # Optionally specify a different action for this audit log
                    Message = "Account for '$($p.DisplayName)' Updated. ObjectId: '$($userResponse.objectId)'"
                    IsError = $false
                })
        }
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
            Action  = "UpdateAccount" # Optionally specify a different action for this audit log
            Message = "Account for '$($p.DisplayName)' not updated. Error: $errorMessage"
            IsError = $false
        })
}

# Send results
$Result = [PSCustomObject]@{
    Success          = $Success
    AuditLogs        = $AuditLogs
    Account          = $Account
    PreviousAccount  = $PreviousAccount

    # Optionally return data for use in other systems
    # ExportData      = [PSCustomObject]@{
    #     DisplayName = $Account.DisplayName
    #     UserName    = $Account.UserName
    #     ExternalId  = $aRef
    # }
}

Write-Output $Result | ConvertTo-Json -Depth 10
