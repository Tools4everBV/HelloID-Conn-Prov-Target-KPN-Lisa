#################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Delete
# Delete account
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
    #region account
    # Define account object
    $account = [PSCustomObject]$actionContext.Data.PsObject.Copy()

    # Define properties to query
    $accountPropertiesToQuery = @("id") + $account.PsObject.Properties.Name | Select-Object -Unique

    # Remove properties of account object with null-values
    $account.PsObject.Properties | ForEach-Object {
        # Remove properties with null-values
        if ($_.Value -eq $null) {
            $account.PsObject.Properties.Remove("$($_.Name)")
        }
    }
    # Convert the properties of account object containing "TRUE" or "FALSE" to boolean
    $account = Convert-StringToBoolean $account
    #endRegion account

    #region Verify account reference
    $actionMessage = "verifying account reference"
    
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw "The account reference could not be found"
    }
    #endregion Verify account reference
    
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

    #region Get account
    # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: GET /api/users/{identifier}
    $actionMessage = "querying account with ID: $($actionContext.References.Account)"

    $getKPNLisaAccountSplatParams = @{
        Uri         = "$($actionContext.Configuration.MWPApiBaseUrl)/users/$($actionContext.References.Account)"
        Method      = "GET"
        Body        = @{
            select = "$($accountPropertiesToQuery -join ',')"
        }
        Verbose     = $false
        ErrorAction = "Stop"
    }

    Write-Verbose "SplatParams: $($getKPNLisaAccountSplatParams | ConvertTo-Json)"

    # Add header after printing splat
    $getKPNLisaAccountSplatParams['Headers'] = $headers

    $getKPNLisaAccountResponse = $null
    $getKPNLisaAccountResponse = Invoke-RestMethod @getKPNLisaAccountSplatParams
    $correlatedAccount = $getKPNLisaAccountResponse
        
    Write-Verbose "Queried account with ID: $($actionContext.References.Account). Result: $($correlatedAccount | ConvertTo-Json)"
    #endregion Get account

    #region Calulate action
    $actionMessage = "calculating action"
    if (($correlatedAccount | Measure-Object).count -eq 1) {
        $actionAccount = "Delete"
    }
    elseif (($correlatedAccount | Measure-Object).count -eq 0) {
        $actionAccount = "NotFound"
    }
    elseif (($correlatedAccount | Measure-Object).count -gt 1) {
        $actionAccount = "MultipleFound"
    }
    #endregion Calulate action
    
    #region Process
    switch ($actionAccount) {
        "Delete" {
            #region Delete account
            # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: DELETE /api/users/{identifier}
            $actionMessage = "deleting account with AccountReference: $($actionContext.References.Account | ConvertTo-Json)"

            $deleteAccountSplatParams = @{
                Uri         = "$($actionContext.Configuration.MWPApiBaseUrl)/users/$($outputContext.AccountReference)"
                Method      = "DELETE"
                ContentType = 'application/json; charset=utf-8'
                Verbose     = $false
                ErrorAction = "Stop"
            }

            Write-Verbose "SplatParams: $($deleteAccountSplatParams | ConvertTo-Json)"

            if (-Not($actionContext.DryRun -eq $true)) {
                # Add header after printing splat
                $deleteAccountSplatParams['Headers'] = $headers

                $deleteAccountResponse = Invoke-RestMethod @deleteAccountSplatParams

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        # Action  = "" # Optional
                        Message = "Deleted account with AccountReference: $($outputContext.AccountReference | ConvertTo-Json)."
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun: Would delete account with AccountReference: $($outputContext.AccountReference | ConvertTo-Json)."
            }
            #endregion Delete account

            break
        }

        "NotFound" {
            #region No account found
            $actionMessage = "skipping deleting account"
        
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    # Action  = "" # Optional
                    Message = "Skipped deleting account with AccountReference: $($actionContext.References.Account | ConvertTo-Json). Reason: No account found with ID: $($actionContext.References.Account). Possibly indicating that it could be deleted, or not correlated."
                    IsError = $true
                })
            #endregion No account found

            break
        }

        "MultipleFound" {
            #region Multiple accounts found
            $actionMessage = "deleting account"

            # Throw terminal error
            throw "Multiple accounts found with ID: $($actionContext.References.Account). Please correct this to ensure the correlation results in a single unique account."
            #endregion Multiple accounts found

            break
        }
    }
    #endregion Process
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

    if ($auditMessage -like "*ResourceNotFound*" -and $auditMessage -like "*User with identifier $($actionContext.References.Account) not found*") {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                # Action  = "" # Optional
                Message = "Skipped deleting account with ID: $($actionContext.References.Account). Reason: No account found with ID: $($actionContext.References.Account). Possibly indicating that it could be deleted, or not correlated."
                IsError = $false
            })
    }
    else {
        Write-Warning $warningMessage

        $outputContext.AuditLogs.Add([PSCustomObject]@{
                # Action  = "" # Optional
                Message = $auditMessage
                IsError = $true
            })
    }
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if (-NOT($outputContext.AuditLogs.IsError -contains $true)) {
        $outputContext.Success = $true
    }
}