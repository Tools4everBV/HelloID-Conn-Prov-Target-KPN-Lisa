#####################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Disable
#
# Version: 1.0.0.0
#####################################################
$VerbosePreference = "Continue"

# Initialize default value's
$Config = $Configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $accountReference | ConvertFrom-Json
$success = $false

#Region internal functions
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
        $headers = [System.Collections.Generic.Dictionary[[String],[String]]]::new()
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
#EndRegion

if (-not($dryRun -eq $true)) {
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

        Write-Verbose "Disable KPN Lisa account for '$($p.DisplayName)'"
        $splatParams = @{
            Uri     = "$($Config.BaseUrl)/Users/$aRef"
            Method  = 'PATCH'
            Headers = $authorizationHeaders
            Body    = [PSCustomObject]@{
                propertyName = "accountEnabled"
                value        = $false
            } | ConvertTo-Json

        }
        $null = Invoke-RestMethod @splatParams
        $success = $true
        $auditMessage = "Account for '$($p.DisplayName)' is disabled"
    }
    catch {
        $ex = $PSItem
        if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorMessage = Resolve-HTTPError -Error $ex
            $auditMessage = "Account for '$($p.DisplayName)' not disabled. Error: $errorMessage"
        }
        else {
            $auditMessage = "Account for '$($p.DisplayName)' not disabled. Error: $($ex.Exception.Message)"
        }
    }
}

$result = [PSCustomObject]@{
    Success          = $success
    Account          = $account
    AccountReference = $aRef
    AuditDetails     = $auditMessage
}

Write-Output $result | ConvertTo-Json -Depth 10
