$Config = $configuration | ConvertFrom-Json
$VerbosePreference = "Continue"

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
#endregion functions

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

$splatParams = @{
    Uri     = "$($Config.BaseUrl)/LicenseProfiles"
    Headers = $authorizationHeaders
    Method  = 'Get'
}
$resultLicenseProfiles = (Invoke-RestMethod @splatParams)

$permissions = $resultLicenseProfiles.value | Select-Object @{
    Name = 'DisplayName'
    Expression = { $_.DisplayName }
}, @{
    Name = "Identification"
    Expression = { @{Reference = $_.groupId } }
}

Write-Output ($permissions | ConvertTo-Json -Depth 10)
