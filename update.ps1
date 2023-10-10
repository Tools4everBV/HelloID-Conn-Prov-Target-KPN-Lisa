#####################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Update
#
# Version: 1.0.0.0
#####################################################

#region Config
$Config = $Configuration | ConvertFrom-Json
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

#region functions
function Get-LisaAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]
        $TenantId,

        [Parameter(Mandatory)]
        [string]
        $ClientId,

        [Parameter(Mandatory)]
        [string]
        $ClientSecret,

        [Parameter(Mandatory)]
        [string]
        $Scope
    )

    try {
        $RestMethod = @{
            Uri         = "https://login.microsoftonline.com/$($TenantId)/oauth2/v2.0/token/"
            ContentType = "application/x-www-form-urlencoded"
            Method      = "Post"
            Body        = @{
                grant_type    = "client_credentials"
                client_id     = $ClientId
                client_secret = $ClientSecret
                scope         = $Scope
            }
        }
        Invoke-RestMethod @RestMethod
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}


function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]
        $ErrorObject
    )

    process {
        $httpError = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }

        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpError.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpError.ErrorMessage = [System.IO.StreamReader]::new(
                $ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }

        Write-Output $httpError
    }
}


function Get-ErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]
        $ErrorObject
    )

    process {
        $errorMessage = [PSCustomObject]@{
            VerboseErrorMessage = $null
            AuditErrorMessage   = $null
        }

        if (
            $ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException' -or
            $ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException'
        ) {
            $httpErrorObject = Resolve-HTTPError -Error $ErrorObject

            $errorMessage.VerboseErrorMessage = $httpErrorObject.ErrorMessage
            $errorMessage.AuditErrorMessage = $httpErrorObject.ErrorMessage
        }

        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($errorMessage.VerboseErrorMessage)) {
            $errorMessage.VerboseErrorMessage = $ErrorObject.Exception.Message
        }
        if ([String]::IsNullOrEmpty($errorMessage.AuditErrorMessage)) {
            $errorMessage.AuditErrorMessage = $ErrorObject.Exception.Message
        }

        Write-Output $errorMessage
    }
}
#endregion functions

# Build the Final Account object
$Account = @{
    givenName                = $p.Name.NickName
    surName                  = $p.Name.FamilyName
#    userPrincipalName        = "$($p.ExternalId)@impegno.onmicrosoft.com"
    displayName              = $p.DisplayName
#    changePasswordNextSignIn = $false
#    usageLocation            = 'NL'
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
        Uri     = "$($Config.BaseUrl)/Users/$($aRef)"
        Method  = 'PATCH'
        Headers = $authorizationHeaders
    }

    # TODO:: Create smaller dryrun scope
    if (-not($dryRun -eq $true)) {
        if ( ($pd.Name.GivenName) -and ($pd.Name.GivenName.Change -eq "Updated") ) {
            $splatParams['Body'] = [PSCustomObject]@{
                propertyName = "givenName"
                value        = $pd.Name.GivenName.New
            } | ConvertTo-Json
            [void] (Invoke-RestMethod @splatParams)
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
                value        = $pd.Name.FamilyName.New
            } | ConvertTo-Json
            [void] (Invoke-RestMethod @splatParams)
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
            [void] (Invoke-RestMethod @splatDeleteManagerParams)
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
            [void] (Invoke-RestMethod @splatUpdateManagerParams)
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
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage) [$($ex.ErrorDetails.Message)]"

    $auditLogs.Add([PSCustomObject]@{
            Action  = "UpdateAccount" # Optionally specify a different action for this audit log
            Message = "Error updating account [$($account.DisplayName) ($($aRef))]. Error Message: $($errorMessage.AuditErrorMessage)."
            IsError = $True
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
