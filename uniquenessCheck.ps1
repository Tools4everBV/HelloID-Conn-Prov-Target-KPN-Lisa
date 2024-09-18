#################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-UniquenessCheck
# Check if fields are unique
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

#region Fields to check
$fieldsToCheck = [PSCustomObject]@{
    "userPrincipalName" = [PSCustomObject]@{
        accountValue   = $actionContext.Data.userPrincipalName
        keepInSyncWith = @("mail") # The properties to keep in sync with, if one of these properties isn't unique, this property wil be treated as not unique as well
        crossCheckOn   = @("mail") # The properties to keep in cross-check on
    }
    "mail"              = [PSCustomObject]@{ # This is the value that is returned to HelloID in NonUniqueFields
        accountValue   = $actionContext.Data.mail
        keepInSyncWith = @("userPrincipalName") # The properties to keep in sync with, if one of these properties isn't unique, this property wil be treated as not unique as well
        crossCheckOn   = @("userPrincipalName") # The properties to keep in cross-check on
    }
}
#endregion Fields to check

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
    
    $createAccessTokenResonse = Invoke-RestMethod @createAccessTokenSplatParams
    
    Write-Verbose "Created access token. Expires in: $($createAccessTokenResonse.expires_in | ConvertTo-Json)"
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
    $headers['Authorization'] = "Bearer $($createAccessTokenResonse.access_token)"
    #endregion Create headers

    if ($actionContext.Operation.ToLower() -ne "create") {
        #region Verify account reference
        $actionMessage = "verifying account reference"
  
        if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
            throw "The account reference could not be found"
        }
        #endregion Verify account reference
    }
    foreach ($fieldToCheck in $fieldsToCheck.PsObject.Properties | Where-Object { -not[String]::IsNullOrEmpty($_.Value.accountValue) }) {
        #region Get account
        # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: GET /api/users
        $actionMessage = "querying account where [$($fieldToCheck.Name)] = [$($fieldToCheck.Value.accountValue)]"

        $filter = "$($fieldToCheck.Name) eq '$($fieldToCheck.Value.accountValue)'" 
        if (($fieldToCheck.Value.crossCheckOn | Measure-Object).Count -ge 1) {
            foreach ($fieldToCrossCheckOn in $fieldToCheck.Value.crossCheckOn) {
                $filter = $filter + " OR $($fieldToCrossCheckOn) eq '$($fieldToCheck.Value.accountValue)'"
            }
        }

        $getKPNLisaAccountSplatParams = @{
            Uri         = "$($actionContext.Configuration.MWPApiBaseUrl)/users"
            Method      = "GET"
            Body        = @{
                filter = "$filter"
                select = "id,$($fieldToCheck.Name)"
            }
            Verbose     = $false
            ErrorAction = "Stop"
        }

        Write-Verbose "SplatParams: $($getKPNLisaAccountSplatParams | ConvertTo-Json)"

        # Add header after printing splat
        $getKPNLisaAccountSplatParams['Headers'] = $headers

        $getKPNLisaAccountResponse = $null
        $getKPNLisaAccountResponse = Invoke-RestMethod @getKPNLisaAccountSplatParams
        $correlatedAccount = $getKPNLisaAccountResponse.Value
    
        Write-Verbose "Queried account where [$($fieldToCheck.Name)] = [$($fieldToCheck.Value.accountValue)]. Result: $($correlatedAccount | ConvertTo-Json)"
        #endregion Get account

        #region Check property uniqueness
        $actionMessage = "checking if property [$($fieldToCheck.Name)] with value [$($fieldToCheck.Value.accountValue)] is unique"
        if (($correlatedAccount | Measure-Object).count -gt 0) {
            if ($actionContext.Operation.ToLower() -ne "create" -and $correlatedAccount.id -eq $actionContext.References.Account) {
                Write-Verbose "Person is using property [$($fieldToCheck.Name)] with value [$($fieldToCheck.Value.accountValue)] themselves."
            }
            else {
                Write-Verbose "Property [$($fieldToCheck.Name)] with value [$($fieldToCheck.Value.accountValue)] is not unique."
                Write-Verbose "In use by: $($correlatedAccount | ConvertTo-Json)."
                [void]$outputContext.NonUniqueFields.Add($fieldToCheck.Name)
        
                if (($fieldToCheck.Value.keepInSyncWith | Measure-Object).Count -ge 1) {
                    foreach ($fieldToKeepInSyncWith in $fieldToCheck.Value.keepInSyncWith | Where-Object { $_ -in $actionContext.Data.PsObject.Properties }) {
                        [void]$outputContext.NonUniqueFields.Add($fieldToKeepInSyncWith)
                    }
                }
            }
        }
        elseif (($correlatedAccount | Measure-Object).count -eq 0) {
            Write-Verbose "Property [$($fieldToCheck.Name)] with value [$($fieldToCheck.Value.accountValue)] is unique."
        }
        #endregion Check property uniqueness
    }

    # Set Success to true
    $outputContext.Success = $true
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

    # Set Success to false
    $outputContext.Success = $false

    Write-Warning $warningMessage

    # Required to write an error as uniqueness check doesn't show auditlog
    Write-Error $auditMessage
}