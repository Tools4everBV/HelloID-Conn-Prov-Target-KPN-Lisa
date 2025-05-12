#################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Import
# Correlate to account
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
    Write-Information 'Starting target account import'

    # Define properties to query
    $importFields = $($actionContext.ImportFields)
    $importFields = $importFields -replace '\..*', ''

    # Add mandatory fields for HelloID to query and return
    if ('id' -notin $importFields) { $importFields += 'id' }
    if ('accountEnabled' -notin $importFields) { $importFields += 'accountEnabled ' }
    if ('displayName' -notin $importFields) { $importFields += 'displayName' }
    if ('userPrincipalName' -notin $importFields) { $importFields += 'userPrincipalName' }

    # Convert to a ',' string
    $fields = $importFields -join ','
    Write-Information "Querying fields [$fields]"

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
    
    Write-Verbose "Created access token. Expires in: $($createAccessTokenResponse.expiresIn | ConvertTo-Json)"
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

    #region Get account
    # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: GET /api/users
    $actionMessage = "querying accounts"

    $existingAccounts = [System.Collections.ArrayList]@()
    do {
        $getKPNLisaUsersSplatParams = @{
            Uri         = "$($actionContext.Configuration.MWPApiBaseUrl)/users"
            Method      = "GET"
            Body        = @{
                Top       = 999
                SkipToken = $Null
            }
            Verbose     = $false
            ErrorAction = "Stop"
        }
        if (-not[string]::IsNullOrEmpty($getKPNLisaUsersResponse.'nextLink')) {
            $getKPNLisaUsersSplatParams.Body.SkipToken = $getKPNLisaUsersResponse.'nextLink'
        }

        Write-Verbose "SplatParams: $($getKPNLisaUsersSplatParams | ConvertTo-Json)"

        # Add header after printing splat
        $getKPNLisaUsersSplatParams['Headers'] = $headers

        $getKPNLisaUsersResponse = $null
        $getKPNLisaUsersResponse = Invoke-RestMethod @getKPNLisaUsersSplatParams

        if ($getKPNLisaUsersResponse.Value -is [array]) {
            [void]$existingAccounts.AddRange($getKPNLisaUsersResponse.Value)
        }
        else {
            [void]$existingAccounts.Add($getKPNLisaUsersResponse.Value)
        }
    } while (-not[string]::IsNullOrEmpty($getKPNLisaUsersResponse.'nextLink'))

    Write-Information "Queried users. Result count: $(($existingAccounts | Measure-Object).Count)"

    # Map the imported data to the account field mappings
    foreach ($account in $existingAccounts) {
        # Make sure the DisplayName has a value
        if ([string]::IsNullOrEmpty($account.displayName)) {
            $account.displayName = $account.id
        }
        # Make sure the Username has a value
        if ([string]::IsNullOrEmpty($account.userPrincipalName)) {
            $account.userPrincipalName = $account.id
        }
        # Return the result
        Write-Output @{
            AccountReference = $account.id
            DisplayName      = $account.displayName
            UserName         = $account.userPrincipalName
            Enabled          = $account.accountEnabled
            Data             = $account
        }
    }

    Write-Information 'Target account import completed'
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

    # Required to write an error as uniqueness check doesn't show auditlog
    Write-Error $auditMessage
}