$c = $configuration | ConvertFrom-Json;
$success = $False;
$auditLogs = New-Object Collections.Generic.List[PSCustomObject];
$aRef = $accountReference | ConvertFrom-Json;
$pRef = $permissionReference | ConvertFrom-Json;

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


        $splatParams = @{
            Uri     = "$($c.BaseUrl)/Users/$($aRef)/groups"
            Headers = $authorizationHeaders
            Method  = 'Post'
            body    = ($pRef.Reference | ConvertTo-Json)
        }
        try {
            $null = (Invoke-RestMethod @splatParams) #If 200 it returns a Empty String
        } catch {
            if ($_ -match "AlreadyMemberOfGroup") {
                Write-Verbose "$($_.Errordetails.message)" -Verbose
            } else {
                throw "Could not add member to group, $($_.Exception.Message) $($_.Errordetails.message)".trim(" ")
            }
        }
        $success = $True;
        $auditLogs.Add([PSCustomObject]@{
                Message = "Permission $($pRef.Reference) added to account $($aRef)";
                IsError = $False;
            });
    } catch {
        Write-Error "$( $_.Exception.Message)"
        $auditLogs.Add([PSCustomObject]@{
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
