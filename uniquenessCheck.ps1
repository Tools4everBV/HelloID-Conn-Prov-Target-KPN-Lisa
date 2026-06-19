#################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-UniquenessCheck
# Check if fields are unique
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

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
    'userPrincipalName' = [PSCustomObject]@{ # Value returned to HelloID in NonUniqueFields.
        systemFieldName = 'userPrincipalName' # Name of the field in KPN Lisa itself, to be used in the query to the system.
        accountValue    = $actionContext.Data.userPrincipalName
        keepInSyncWith  = @('mail') # Properties to synchronize with. If this property isn't unique, these properties will also be treated as non-unique.
        crossCheckOn    = @('mail', 'proxyAddresses') # Properties to cross-check for uniqueness.
    }
    'mail'              = [PSCustomObject]@{ # Value returned to HelloID in NonUniqueFields.
        systemFieldName = 'mail' # Name of the field in KPN Lisa itself, to be used in the query to the system.
        accountValue    = $actionContext.Data.mail
        keepInSyncWith  = @('userPrincipalName') # Properties to synchronize with. If this property isn't unique, these properties will also be treated as non-unique.
        crossCheckOn    = @('userPrincipalName', 'proxyAddresses') # Properties to cross-check for uniqueness.
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
        $actionMessage = "calculating filter account for property [$($fieldToCheck.Name)] with value [$($fieldToCheck.Value.accountValue)]"

        $filter = "$($fieldToCheck.Value.systemFieldName) eq '$($fieldToCheck.Value.accountValue)'" 
        if (@($fieldToCheck.Value.crossCheckOn).Count -ge 1) {
            foreach ($fieldToCrossCheckOn in $fieldToCheck.Value.crossCheckOn) {
                if ($fieldToCrossCheckOn -eq "proxyAddresses") {
                    # Special handling for proxyAddresses which uses the any() operator
                    $filter = $filter + " OR proxyAddresses/any(c:c eq 'SMTP:$($fieldToCheck.Value.accountValue)')"
                }
                else {
                    $filter = $filter + " OR $($fieldToCrossCheckOn) eq '$($fieldToCheck.Value.accountValue)'"
                }
            }
        }

        $actionMessage = "querying KPN Lisa account where [filter] = [$filter]"

        # Build select properties list
        $selectProperties = @('id', $fieldToCheck.Value.systemFieldName)
        if (@($fieldToCheck.Value.crossCheckOn).Count -ge 1) {
            $selectProperties += $fieldToCheck.Value.crossCheckOn
        }
        $selectPropertiesString = ($selectProperties | Select-Object -Unique) -join ','

        $getKPNLisaAccountSplatParams = @{
            Uri         = "$($actionContext.Configuration.MWPApiBaseUrl)/users"
            Method      = "GET"
            Body        = @{
                filter = "$filter"
                select = $selectPropertiesString
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
    
        Write-Verbose "Queried KPN Lisa account where [filter] = [$filter]. Result count: $(@($correlatedAccount).Count)"
        #endregion Get account

        #region Check property uniqueness
        $actionMessage = "checking if property [$($fieldToCheck.Name)] with value [$($fieldToCheck.Value.accountValue)] is unique"
        if (@($correlatedAccount).count -gt 0) {
            if ($actionContext.Operation.ToLower() -ne "create" -and $correlatedAccount.id -eq $actionContext.References.Account) {
                Write-Information "Person is using property [$($fieldToCheck.Name)] with value [$($fieldToCheck.Value.accountValue)] themselves."
            }
            else {
                # Determine if this is a direct match or cross-check match
                if ($correlatedAccount.$($fieldToCheck.Value.systemFieldName) -eq $fieldToCheck.Value.accountValue) {
                    # Direct match: The field itself contains the value
                    Write-Warning "Property [$($fieldToCheck.Name)] with value [$($fieldToCheck.Value.accountValue)] is not unique. It is currently in use by account with ID [$($correlatedAccount.id)]."
                }
                else {
                    # Cross-check match: The value exists in one of the crossCheckOn fields
                    $matchedFieldName = $null
                    $matchedFieldValue = $null
                    
                    if (@($fieldToCheck.Value.crossCheckOn).Count -ge 1) {
                        foreach ($fieldToCrossCheckOn in $fieldToCheck.Value.crossCheckOn) {
                            if ($fieldToCrossCheckOn -eq "proxyAddresses") {
                                # Special handling for proxyAddresses (array field)
                                if ($correlatedAccount.proxyAddresses -contains "SMTP:$($fieldToCheck.Value.accountValue)") {
                                    $matchedFieldName = "proxyAddresses"
                                    $matchedFieldValue = "SMTP:$($fieldToCheck.Value.accountValue)"
                                    break
                                }
                            }
                            else {
                                # Regular field check
                                if ($correlatedAccount.$fieldToCrossCheckOn -eq $fieldToCheck.Value.accountValue) {
                                    $matchedFieldName = $fieldToCrossCheckOn
                                    $matchedFieldValue = $fieldToCheck.Value.accountValue
                                    break
                                }
                            }
                        }
                    }
                    
                    if ($matchedFieldName) {
                        Write-Warning "Property [$($fieldToCheck.Name)] with value [$($fieldToCheck.Value.accountValue)] is not unique due to cross-check. The value exists as [$matchedFieldName] = [$matchedFieldValue] in use by account with ID [$($correlatedAccount.id)]."
                    }
                    else {
                        # Fallback if we can't determine the exact field
                        Write-Warning "Property [$($fieldToCheck.Name)] with value [$($fieldToCheck.Value.accountValue)] is not unique. In use by account with ID [$($correlatedAccount.id)]."
                    }
                }
                
                [void]$outputContext.NonUniqueFields.Add($fieldToCheck.Name)
        
                if (@($fieldToCheck.Value.keepInSyncWith).Count -ge 1) {
                    foreach ($fieldToKeepInSyncWith in $fieldToCheck.Value.keepInSyncWith | Where-Object { $_ -in $actionContext.Data.PsObject.Properties.Name }) {
                        Write-Warning "Property [$fieldToKeepInSyncWith] is marked as non-unique because it is configured to keepInSyncWith [$($fieldToCheck.Name)], which is not unique."
                        [void]$outputContext.NonUniqueFields.Add($fieldToKeepInSyncWith)
                    }
                }
            }
        }
        elseif (@($correlatedAccount).count -eq 0) {
            Write-Information "Property [$($fieldToCheck.Name)] with value [$($fieldToCheck.Value.accountValue)] is unique."
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
finally {
    $outputContext.NonUniqueFields = @($outputContext.NonUniqueFields | Sort-Object -Unique)
}
