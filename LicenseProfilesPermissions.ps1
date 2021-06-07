$c = $configuration | ConvertFrom-Json
$VerbosePreference = "Continue"

#region functions
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
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
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
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

#endregion functions

$splatGetTokenParams = @{
    TenantId     = $c.TenantId
    ClientId     = $c.ClientId
    ClientSecret = $c.ClientSecret
    Scope        = $c.Scope
}

$accessToken = (Get-LisaAccessToken @splatGetTokenParams).access_token
$authorizationHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$authorizationHeaders.Add("Authorization", "Bearer $accessToken")
$authorizationHeaders.Add("Content-Type", "application/json")
$authorizationHeaders.Add("Mwp-Api-Version", "1.0")


$splatParams = @{
    Uri     = "$($c.BaseUrl)/LicenseProfiles"
    Headers = $authorizationHeaders
    Method  = 'Get'
}
$resultLicenseProfiles = (Invoke-RestMethod @splatParams)

$permissions = $resultLicenseProfiles.value | Select-Object @{Name = 'DisplayName'; Expression = { $_.DisplayName } },
@{Name = "Identification"; Expression = { @{Reference = $_.groupId } } }

Write-Output ($permissions | ConvertTo-Json -Depth 10)