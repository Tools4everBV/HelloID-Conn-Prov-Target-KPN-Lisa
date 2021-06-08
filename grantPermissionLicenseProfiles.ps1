$p = $person | ConvertFrom-Json;
$aRef = $accountReference | ConvertFrom-Json;
$pRef = $permissionReference | ConvertFrom-Json;
$c = $configuration | ConvertFrom-Json;
$success = $False;
$auditLogs = New-Object Collections.Generic.List[PSCustomObject];

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

if (-Not($dryRun -eq $true)) {
    try {
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

        $body = @{
            groupId = $pRef.Reference
        }

        $splatParams = @{
            Uri     = "$($c.BaseUrl)/Users/$($aRef)/LicenseProfiles"
            Headers = $authorizationHeaders
            Method  = 'Post'
            body    = ($body | ConvertTo-Json)
        }
        $null = (Invoke-RestMethod @splatParams) #If 200 it returns a Empty String
        $success = $True;
        $auditLogs.Add([PSCustomObject]@{
                Action  = "GrantPermission";
                Message = "Permission $($pRef.Reference) added to account $($aRef)";
                IsError = $False;
            });
    } catch {
        Write-Verbose $($_) -Verbose
        $auditLogs.Add([PSCustomObject]@{
                Action  = "GrantPermission";
                Message = "Failed to add permission $($pRef.Reference) to account $($aRef)";
                IsError = $true;
            });
    }
}



# Send results
$result = [PSCustomObject]@{
    Success   = $success;
    AuditLogs = $auditLogs;
    Account   = [PSCustomObject]@{ };
};

Write-Output $result | ConvertTo-Json -Depth 10;
