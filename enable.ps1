#####################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Enable
#
# Version: 1.0.0.0
#####################################################

#region Config
$Config = $Configuration | ConvertFrom-Json
#endregion Config

#region default properties
$p = $person | ConvertFrom-Json
$m = $manager | ConvertFrom-Json

$aRef = $accountReference | ConvertFrom-Json
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

    Write-Verbose "Enable KPN Lisa account for '$($p.DisplayName)'"
    $splatParams = @{
        Uri     = "$($Config.BaseUrl)/Users/$aRef"
        Method  = 'PATCH'
        Headers = $authorizationHeaders
        Body    = [PSCustomObject]@{
            propertyName = "accountEnabled"
            value        = $true
        } | ConvertTo-Json
    }

    if (-not($dryRun -eq $true)) {
        $null = Invoke-RestMethod @splatParams
    }

    $success = $true

    $AuditLogs.Add([PSCustomObject]@{
            Action  = "EnableAccount"
            Message = "Account for '$($p.DisplayName)' is enabled"
            IsError = $False
        })
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
            Action  = "EnableAccount"
            Message = "Account for '$($p.DisplayName)' not enabled. Error: $errorMessage"
            IsError = $True
        })
}


$result = [PSCustomObject]@{
    Success   = $success
    AuditLogs = $AuditLogs
    Account   = $account
}

Write-Output $result | ConvertTo-Json -Depth 10
