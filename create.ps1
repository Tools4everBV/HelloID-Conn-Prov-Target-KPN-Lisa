#################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Create
# Create and update or correlate to account
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
    if ($obj -is [PSCustomObject]) {
        foreach ($property in $obj.PSObject.Properties) {
            $value = $property.Value
            if ($value -is [string]) {
                $lowercaseValue = $value.ToLower()
                if ($lowercaseValue -eq "true") {
                    $obj.$($property.Name) = $true
                }
                elseif ($lowercaseValue -eq "false") {
                    $obj.$($property.Name) = $false
                }
            }
            elseif ($value -is [PSCustomObject] -or $value -is [System.Collections.IDictionary]) {
                $obj.$($property.Name) = Convert-StringToBoolean $value
            }
            elseif ($value -is [System.Collections.IList]) {
                for ($i = 0; $i -lt $value.Count; $i++) {
                    $value[$i] = Convert-StringToBoolean $value[$i]
                }
                $obj.$($property.Name) = $value
            }
        }
    }
    return $obj
}
#endregion functions

try {
    #region account
    # Define correlation
    $correlationField = $actionContext.CorrelationConfiguration.accountField
    $correlationValue = $actionContext.CorrelationConfiguration.accountFieldValue

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

    #region Verify correlation configuration and properties
    $actionMessage = "verifying correlation configuration and properties"

    if ($actionContext.CorrelationConfiguration.Enabled -eq $true) {
        if ([string]::IsNullOrEmpty($correlationField)) {
            throw "Correlation is enabled but not configured correctly."
        }
        
        if ([string]::IsNullOrEmpty($correlationValue)) {
            throw "The correlation value for [$correlationField] is empty. This is likely a mapping issue."
        }
    }
    else {
        Write-Warning "Correlation is disabled."
    }
    #endregion Verify correlation configuration and properties
    
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
    
    Write-Verbose "Created access token. Result: $($createAccessTokenResonse | ConvertTo-Json)"
    #endregion Create access token
    
    #region Create headers
    $actionMessage = "creating headers"
    
    $headers = @{
        "Authorization"   = "Bearer $($createAccessTokenResonse.access_token)"
        "Accept"          = "application/json"
        "Content-Type"    = "application/json;charset=utf-8"
        "Mwp-Api-Version" = "1.0"
    }
    
    Write-Verbose "Created headers. Result: $($headers | ConvertTo-Json)."
    #endregion Create headers

    #region Get account
    # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: GET /api/users
    $actionMessage = "querying account where [$($correlationField)] = [$($correlationValue)]"

    $getKPNLisaAccountSplatParams = @{
        Uri         = "$($actionContext.Configuration.MWPApiBaseUrl)/users"
        Method      = "GET"
        Body        = @{
            filter = "$($correlationField) eq '$($correlationValue)'"
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
    $correlatedAccount = $getKPNLisaAccountResponse.Value
        
    Write-Verbose "Queried account where [$($correlationField)] = [$($correlationValue)]. Result: $($correlatedAccount  | ConvertTo-Json)"
    #endregion Get account

    #region Calulate action
    $actionMessage = "calculating action"
    if (($correlatedAccount | Measure-Object).count -eq 1) {
        $actionAccount = "Correlate"
    }
    elseif (($correlatedAccount | Measure-Object).count -eq 0) {
        $actionAccount = "Create"
    }
    elseif (($correlatedAccount | Measure-Object).count -gt 1) {
        $actionAccount = "MultipleFound"
    }
    #endregion Calulate action
    
    #region Process
    switch ($actionAccount) {
        "Create" {
            #region Create account                  
            # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: POST /api/users
            $actionMessage = "creating account with displayName [$($account.displayName)] and userPrincipalName [$($account.userPrincipalName)]"

            # Create account with only required fields
            $requiredFields = @("changePasswordNextSignIn", "displayName", "preferredLanguage", "usageLocation", "userPrincipalName", "employeeId", "$correlationField")
            $createAccountBody = [PSCustomObject]@{}
            foreach ($accountProperty in $account.PsObject.Properties | Where-Object { $null -ne $_.Value -and $_.Name -in $requiredFields }) {
                $createAccountBody | Add-Member -MemberType NoteProperty -Name $accountProperty.Name -Value $accountProperty.Value -Force
            }

            $createAccountSplatParams = @{
                Uri         = "$($actionContext.Configuration.MWPApiBaseUrl)/users"
                Method      = "POST"
                Body        = ($createAccountBody | ConvertTo-Json -Depth 10)
                ContentType = 'application/json; charset=utf-8'
                Verbose     = $false
                ErrorAction = "Stop"
            }

            Write-Verbose "SplatParams: $($createAccountSplatParams | ConvertTo-Json)"

            if (-Not($actionContext.DryRun -eq $true)) {
                # Add header after printing splat
                $createAccountSplatParams['Headers'] = $headers

                $createAccountResponse = Invoke-RestMethod @createAccountSplatParams
                $createdAccount = $createAccountResponse

                #region Set AccountReference and add AccountReference to Data
                $outputContext.AccountReference = "$($createdAccount.objectId)"
                $outputContext.Data | Add-Member -MemberType NoteProperty -Name "id" -Value "$($createdAccount.objectId)" -Force
                #endregion Set AccountReference and add AccountReference to Data

                #region Set Password with temporary password, generated by KPN Lisa
                $outputContext.Data | Add-Member -MemberType NoteProperty -Name "password" -Value "$($createdAccount.temporaryPassword)" -Force
                #endregion Set Password with temporary password, generated by KPN Lisa

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        # Action  = "" # Optional
                        Message = "Created account with displayName [$($createAccountBody.displayName)] and userPrincipalName [$($createAccountBody.userPrincipalName)] with AccountReference: $($outputContext.AccountReference | ConvertTo-Json)."
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun: Would create account with displayName [$($createAccountBody.displayName)] and userPrincipalName [$($createAccountBody.userPrincipalName)]."
            }
            #endregion Create account

            #region Update account
            # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: PATCH /api/users/{identifier}/bulk
            $actionMessage = "updating created account with AccountReference: $($outputContext.AccountReference | ConvertTo-Json)"

            # Update account with all other fields than the required fields
            $updateAccountBody = [PSCustomObject]@{}
            foreach ($accountProperty in $account.PsObject.Properties | Where-Object { $null -ne $_.Value -and $_.Name -notin $requiredFields }) {
                $updateAccountBody | Add-Member -MemberType NoteProperty -Name $accountProperty.Name -Value $accountProperty.Value -Force
            }

            $updateAccountSplatParams = @{
                Uri         = "$($actionContext.Configuration.MWPApiBaseUrl)/users/$($outputContext.AccountReference)/bulk"
                Method      = "PATCH"
                Body        = ($updateAccountBody | ConvertTo-Json -Depth 10)
                ContentType = 'application/json; charset=utf-8'
                Verbose     = $false
                ErrorAction = "Stop"
            }

            Write-Verbose "SplatParams: $($updateAccountSplatParams | ConvertTo-Json)"

            if (-Not($actionContext.DryRun -eq $true)) {
                # Add header after printing splat
                $updateAccountSplatParams['Headers'] = $headers

                $updateAccountResponse = Invoke-RestMethod @updateAccountSplatParams

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        # Action  = "" # Optional
                        Message = "Updated created account with AccountReference: $($outputContext.AccountReference | ConvertTo-Json). Updated properties [$($updateAccountBody | ConvertTo-Json)."
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun: Would update created account. Updated properties [$($updateAccountBody | ConvertTo-Json)."
            }
            #endregion Update account

            #region Manager
            if ($actionContext.Configuration.setManagerOnCreate -eq $true) {
                #region Calulate manager action
                if (-not[String]::IsNullOrEmpty(($actionContext.References.ManagerAccount))) {
                    $actionManager = "Set"
                    $currentKPNLisaManagerAccountId = $actionContext.References.ManagerAccount
                }
                else {
                    $actionManager = "AccountReferenceEmpty"
                }

                #endregion Calulate manager action

                switch ($actionManager) {
                    "Set" {
                        #region Set Manager
                        # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: PUT /api/users/{identifier}/manager
                        $actionMessage = "setting manager for created account"

                        $setManagerSplatParams = @{
                            Uri         = "$($actionContext.Configuration.MWPApiBaseUrl)/users/$($outputContext.AccountReference)/manager"
                            Method      = "PUT"
                            # Body is a single string, the id of the account beloning tot the manager
                            Body        = ($actionContext.References.ManagerAccount | ConvertTo-Json -Depth 10)
                            Verbose     = $false
                            ErrorAction = "Stop"
                        }

                        Write-Verbose "SplatParams: $($setManagerSplatParams | ConvertTo-Json)"

                        if (-Not($actionContext.DryRun -eq $true)) {
                            # Add header after printing splat
                            $setManagerSplatParams['Headers'] = $headers

                            $setManagerResponse = Invoke-RestMethod @setManagerSplatParams

                            #region Set ManagerId
                            $outputContext.Data | Add-Member -MemberType NoteProperty -Name "managerId" -Value $actionContext.References.ManagerAccount -Force
                            #endregion Set ManagerId

                            $outputContext.AuditLogs.Add([PSCustomObject]@{
                                    # Action  = "" # Optional
                                    Message = "Set manager for created account with AccountReference: $($outputContext.AccountReference | ConvertTo-Json). New value: $($currentKPNLisaManagerAccountId | ConvertTo-Json)."
                                    IsError = $false
                                })
                        }
                        else {
                            Write-Warning "DryRun: Would set manager for created account. New value: $($currentKPNLisaManagerAccountId | ConvertTo-Json)"
                        }
                        #endregion Set Manager

                        break
                    }

                    "AccountReferenceEmpty" {
                        #region No account found
                        $actionMessage = "setting manager for created account"

                        $outputContext.AuditLogs.Add([PSCustomObject]@{
                                # Action  = "" # Optional
                                Message = "Skipped setting manager for created account with AccountReference: $($outputContext.AccountReference | ConvertTo-Json). Reason: Manager AccountReference is empty."
                                IsError = $false
                            })
                        #endregion No account found
        
                        break
                    }
                }
            }
            #endregion Manager

            break
        }

        "Correlate" {
            #region Correlate account
            $actionMessage = "correlating to account"

            $outputContext.AccountReference = "$($correlatedAccount.id)"
            $outputContext.Data = $correlatedAccount.PsObject.Copy()

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = "CorrelateAccount" # Optionally specify a different action for this audit log
                    Message = "Correlated to account with AccountReference: $($outputContext.AccountReference | ConvertTo-Json) on [$($correlationField)] = [$($correlationValue)]."
                    IsError = $false
                })

            $outputContext.AccountCorrelated = $true
            #endregion Correlate account

            break
        }

        "MultipleFound" {
            #region Multiple accounts found
            $actionMessage = "correlating to account"

            # Throw terminal error
            throw "Multiple accounts found where [$($correlationField)] = [$($correlationValue)]. Please correct this so the persons are unique."
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

    Write-Warning $warningMessage

    $outputContext.AuditLogs.Add([PSCustomObject]@{
            # Action  = "" # Optional
            Message = $auditMessage
            IsError = $true
        })
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if (-NOT($outputContext.AuditLogs.IsError -contains $true)) {
        $outputContext.Success = $true
    }

    # Check if accountreference is set, if not set, set this with default value as this must contain a value
    if ([String]::IsNullOrEmpty($outputContext.AccountReference) -and $actionContext.DryRun -eq $true) {
        $outputContext.AccountReference = "DryRun: Currently not available"
    }
}