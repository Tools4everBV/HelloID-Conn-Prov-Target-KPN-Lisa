#################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Permissions-Teams-List
# List teams as permissions
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($actionContext.Configuration.isDebug) {
    $true { $VerbosePreference = "Continue" }
    $false { $VerbosePreference = "SilentlyContinue" }
}
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region functions
function Resolve-KPNLisaError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {

            $errorObjectConverted = $ErrorObject.ErrorDetails.Message | ConvertFrom-Json -ErrorAction Stop

            if ($null -ne $errorObjectConverted.Error) {
                if ($null -ne $errorObjectConverted.Error.Message) {
                    $httpErrorObj.FriendlyMessage = $errorObjectConverted.Error.Message

                    if ($null -ne $errorObjectConverted.Error.Code) { 
                        $httpErrorObj.FriendlyMessage = $httpErrorObj.FriendlyMessage + ". Error code: $($errorObjectConverted.Error.Code)"
                    }

                    if ($null -ne $errorObjectConverted.ErrorDetails) { 
                        $httpErrorObj.FriendlyMessage = $httpErrorObj.FriendlyMessage + ". Additional details: $($errorObjectConverted.ErrorDetails | ConvertTo-Json)"
                    }
                }
                else {
                    $httpErrorObj.FriendlyMessage = $errorObjectConverted.Error
                }
            }
            else {
                $httpErrorObj.FriendlyMessage = $ErrorObject
            }
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}

function Convert-StringToBoolean($obj) {
    foreach ($property in $obj.PSObject.Properties) {
        $value = $property.Value
        if ($value -is [string]) {
            try {
                $obj.$($property.Name) = [System.Convert]::ToBoolean($value)
            }
            catch {
                # Handle cases where conversion fails
                $obj.$($property.Name) = $value
            }
        }
    }
    return $obj
}
#endregion functions

try {  
    #region Create access token
    $actionMessage = "creating access token"
    
    $createAccessTokenBody = @{
        grant_type    = "client_credentials"
        client_id     = $actionContext.Configuration.EntraIDAppId
        client_secret = $actionContext.Configuration.EntraIDAppSecret
        scope         = $actionContext.Configuration.KPNMWPScope
    }
    
    $createAccessTokenSplatParams = @{
        Uri             = "https://login.microsoftonline.com/$($actionContext.Configuration.EntraIDTenantID)/oauth2/v2.0/token/"
        Headers         = $headers
        Method          = "POST"
        ContentType     = "application/x-www-form-urlencoded"
        UseBasicParsing = $true
        Body            = $createAccessTokenBody
        Verbose         = $false
        ErrorAction     = "Stop"
    }
    
    $createAccessTokenResponse = Invoke-RestMethod @createAccessTokenSplatParams
    
    Write-Verbose "Created access token. Expires in: $($createAccessTokenResponse.expires_in | ConvertTo-Json)"
    #endregion Create access token
    
    #region Create headers
    $actionMessage = "creating headers"
    
    $headers = @{
        "Accept"          = "application/json"
        "Content-Type"    = "application/json;charset=utf-8"
        "Mwp-Api-Version" = "1.0"
    }
    
    Write-Verbose "Created headers. Result (without Authorization): $($headers | ConvertTo-Json)."

    # Add Authorization after printing splat
    $headers['Authorization'] = "Bearer $($createAccessTokenResponse.access_token)"
    #endregion Create headers

    #region Get Teams
    # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: GET /api/teams
    $actionMessage = "querying teams"

    $kpnLisaTeams = [System.Collections.ArrayList]@()
    do {
        $getKPNLisaTeamsSplatParams = @{
            Uri         = "$($actionContext.Configuration.MWPApiBaseUrl)/teams"
            Method      = "GET"
            Body        = @{
                Top       = 999
                SkipToken = $Null
            }
            Verbose     = $false
            ErrorAction = "Stop"
        }
        if (-not[string]::IsNullOrEmpty($getKPNLisaTeamsResponse.'nextLink')) {
            $getKPNLisaTeamsSplatParams.Body.SkipToken = $getKPNLisaTeamsResponse.'nextLink'
        }

        Write-Verbose "SplatParams: $($getKPNLisaTeamsSplatParams | ConvertTo-Json)"

        # Add header after printing splat
        $getKPNLisaTeamsSplatParams['Headers'] = $headers

        $getKPNLisaTeamsResponse = $null
        $getKPNLisaTeamsResponse = Invoke-RestMethod @getKPNLisaTeamsSplatParams

        if ($getKPNLisaTeamsResponse.Value -is [array]) {
            [void]$kpnLisaTeams.AddRange($getKPNLisaTeamsResponse.Value)
        }
        else {
            [void]$kpnLisaTeams.Add($getKPNLisaTeamsResponse.Value)
        }
    } while (-not[string]::IsNullOrEmpty($getKPNLisaTeamsResponse.'nextLink'))

    Write-Information "Queried teams. Result count: $(($kpnLisaTeams | Measure-Object).Count)"
    #endregion Get Teams

    #region Send results to HelloID
    $kpnLisaTeams | ForEach-Object {
        # Shorten DisplayName to max. 100 chars
        $displayName = "Team - $($_.displayName)"
        $displayName = $displayName.substring(0, [System.Math]::Min(100, $displayName.Length)) 
        
        $outputContext.Permissions.Add(
            @{
                displayName    = $displayName
                identification = @{
                    Id   = $_.id
                    Name = $_.displayName
                }
            }
        )
    }
    #endregion Send results to HelloID
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-KPNLisaError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }

    Write-Warning $warningMessage

    # Required to write an error as the listing of permissions doesn't show auditlog
    Write-Error $auditMessage
}