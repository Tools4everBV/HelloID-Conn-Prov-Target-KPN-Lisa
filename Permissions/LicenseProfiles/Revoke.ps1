$Config = $configuration | ConvertFrom-Json
$success = $False
$auditLogs = [Collections.Generic.List[PSCustomObject]]::new()

$p = $person | ConvertFrom-Json
$aRef = $accountReference | ConvertFrom-Json
$pRef = $permissionReference | ConvertFrom-Json

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

if (-Not($dryRun -eq $true)) {
    try {
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
            Uri     = "$($Config.BaseUrl)/Users/$($aRef)/LicenseProfiles/$($pRef.Reference)"
            Headers = $authorizationHeaders
            Method  = 'Delete'
        }

        [void] (Invoke-RestMethod @splatParams) #If 200 it returns a Empty String

        $success = $True

        $auditLogs.Add([PSCustomObject]@{
                Message = "Permission $($pRef.Reference) removed from account $($aRef)"
                IsError = $False
            })
    }
    catch {
        #write-verbose -verbose "($_)"
        $auditLogs.Add([PSCustomObject]@{
                Message = "Failed to remove permission $($pRef.Reference) from account $($aRef)"
                IsError = $False
            })
    }
}

# Send results
$result = [PSCustomObject]@{
    Success   = $success
    AuditLogs = $auditLogs
    Account   = [PSCustomObject]@{ }
}

Write-Output $result | ConvertTo-Json -Depth 10
