#################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Update
# Update account
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
    $correlationField = "Id"
    $correlationValue = $actionContext.References.Account

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

    # Define properties to compare for update
    $accountPropertiesToCompare = $account.PsObject.Properties.Name
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
    # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: GET /api/users/{identifier}
    $actionMessage = "querying account where [$($correlationField)] = [$($correlationValue)]"

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
        
    Write-Verbose "Queried account where [$($correlationField)] = [$($correlationValue)]. Result: $($correlatedAccount | ConvertTo-Json)"
    #endregion Get account

    #region Calulate action
    $actionMessage = "calculating action"
    if (($correlatedAccount | Measure-Object).count -eq 1) {
        $actionMessage = "comparing current account to mapped properties"

        # Set Previous data (if there are no changes between PreviousData and Data, HelloID will log "update finished with no changes")
        $outputContext.PreviousData = $correlatedAccount.PsObject.Copy()

        if ($actionContext.Configuration.updateManagerOnUpdate -eq $true) {
            #region Get manager of account
            # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: GET /api/users/{identifier}/manager
            $actionMessage = "querying manager of account with AccountReference: $($actionContext.References.Account | ConvertTo-Json)"
    
            $getKPNLisaAccountManagerSplatParams = @{
                Uri         = "$($actionContext.Configuration.MWPApiBaseUrl)/users/$($actionContext.References.Account)/manager"
                Method      = "GET"
                Verbose     = $false
                ErrorAction = "Stop"
            }
    
            Write-Verbose "SplatParams: $($getKPNLisaAccountSplatParams | ConvertTo-Json)"
    
            # Add header after printing splat
            $getKPNLisaAccountManagerSplatParams['Headers'] = $headers
    
            $getKPNLisaAccountManagerResponse = $null
            $getKPNLisaAccountManagerResponse = Invoke-RestMethod @getKPNLisaAccountManagerSplatParams
            $previousManagerId = $getKPNLisaAccountManagerResponse.id
            
            Write-Verbose "Queried manager of account with AccountReference: $($actionContext.References.Account | ConvertTo-Json). Result: $($getKPNLisaAccountManagerResponse | ConvertTo-Json)"
            #endregion Get manager of  account
    
            #region Calulate manager action
            if ($actionContext.References.ManagerAccount -ne $previousManagerId) {
                if (-not[String]::IsNullOrEmpty(($actionContext.References.ManagerAccount))) {
                    $actionManager = "Update"
                }
                else {
                    $actionManager = "Clear"
                }
            }
            else {
                $actionManager = "NoChanges"
            }
            #endregion Calulate manager action

            # Add managerId to Previous data
            $outputContext.PreviousData | Add-Member -MemberType NoteProperty -Name "managerId" -Value $previousManagerId -Force
        }

        # Create reference object from correlated account
        $accountReferenceObject = [PSCustomObject]@{}
        foreach ($correlatedAccountProperty  in ($correlatedAccount | Get-Member -MemberType NoteProperty)) {
            # Add property using -join to support array values
            $accountReferenceObject | Add-Member -MemberType NoteProperty -Name $correlatedAccountProperty.Name -Value ($correlatedAccount.$($correlatedAccountProperty.Name) -join ",") -Force
        }

        # Create difference object from mapped properties
        $accountDifferenceObject = [PSCustomObject]@{}
        foreach ($accountProperty in $account.PSObject.Properties) {
            # Add property using -join to support array values
            $accountDifferenceObject | Add-Member -MemberType NoteProperty -Name $accountProperty.Name -Value ($accountProperty.Value -join ",") -Force
        }

        $accountSplatCompareProperties = @{
            ReferenceObject  = $accountReferenceObject.PSObject.Properties | Where-Object { $_.Name -in $accountPropertiesToCompare }
            DifferenceObject = $accountDifferenceObject.PSObject.Properties | Where-Object { $_.Name -in $accountPropertiesToCompare }
        }

        if ($null -ne $accountSplatCompareProperties.ReferenceObject -and $null -ne $accountSplatCompareProperties.DifferenceObject) {
            $accountPropertiesChanged = Compare-Object @accountSplatCompareProperties -PassThru
            $accountOldProperties = $accountPropertiesChanged | Where-Object { $_.SideIndicator -eq "<=" }
            $accountNewProperties = $accountPropertiesChanged | Where-Object { $_.SideIndicator -eq "=>" }
        }

        if ($accountNewProperties) {
            # Create custom object with old and new values
            $accountChangedPropertiesObject = [PSCustomObject]@{
                OldValues = @{}
                NewValues = @{}
            }

            # Add the old properties to the custom object with old and new values
            foreach ($accountoOldProperty in $accountOldProperties) {
                $accountChangedPropertiesObject.OldValues.$($accountoOldProperty.Name) = $accountoOldProperty.Value
            }

            # Add the new properties to the custom object with old and new values
            foreach ($accountNewProperty in $accountNewProperties) {
                $accountChangedPropertiesObject.NewValues.$($accountNewProperty.Name) = $accountNewProperty.Value
            }

            Write-Verbose "Changed properties: $($accountChangedPropertiesObject | ConvertTo-Json)"

            $actionAccount = "Update"
        }
        else {
            $actionAccount = "NoChanges"
        }            

        Write-Verbose "Compared current account to mapped properties. Result: $actionAccount"
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
        "Update" {
            #region Update account
            # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: PATCH /api/users/{identifier}/bulk
            $actionMessage = "updating account with AccountReference: $($actionContext.References.Account | ConvertTo-Json)"

            # Set $outputContext.Data with correlated account
            $outputContext.Data = $correlatedAccount.PsObject.Copy()
            
            # Create custom account object for update and set with updated properties
            $updateAccountBody = [PSCustomObject]@{}
            foreach ($accountNewProperty in $accountNewProperties) {
                $updateAccountBody | Add-Member -MemberType NoteProperty -Name $accountNewProperty.Name -Value $accountNewProperty.Value -Force

                # Update $outputContext.Data with updated fields
                $outputContext.Data | Add-Member -MemberType NoteProperty -Name $accountNewProperty.Name -Value $accountNewProperty.Value -Force
            }
            # Convert the properties of custom account object for update containing "TRUE" or "FALSE" to boolean 
            $updateAccountBody = Convert-StringToBoolean $updateAccountBody

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
                        Message = "Updated account with AccountReference: $($outputContext.AccountReference | ConvertTo-Json). Old values: $($accountChangedPropertiesObject.oldValues | ConvertTo-Json). New values: $($accountChangedPropertiesObject.newValues | ConvertTo-Json)."
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun: Would update account with AccountReference: $($outputContext.AccountReference | ConvertTo-Json). Old values: $($accountChangedPropertiesObject.oldValues | ConvertTo-Json). New values: $($accountChangedPropertiesObject.newValues | ConvertTo-Json)."
            }
            #endregion Update account

            break
        }

        "NoChanges" {
            #region No changes
            $actionMessage = "skipping updating account"

            $outputContext.Data = $correlatedAccount.PsObject.Copy()

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    # Action  = "" # Optional
                    Message = "Skipped updating account with AccountReference: $($actionContext.References.Account | ConvertTo-Json). Reason: No changes."
                    IsError = $false
                })
            #endregion No changes

            break
        }

        "NotFound" {
            #region No account found
            $actionMessage = "updating account"

            # Throw terminal error
            throw "No account found where [$($correlationField)] = [$($correlationValue)]."
            #endregion No account found

            break
        }

        "MultipleFound" {
            #region Multiple accounts found
            $actionMessage = "updating account"

            # Throw terminal error
            throw "Multiple accounts found where [$($correlationField)] = [$($correlationValue)]. Please correct this to ensure the correlation results in a single unique account."
            #endregion Multiple accounts found

            break
        }
    }
    #endregion Process

    #region Manager
    if ($actionContext.Configuration.updateManagerOnUpdate -eq $true) {      
        switch ($actionManager) {
            "Update" {
                #region Set Manager
                # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: PUT /api/users/{identifier}/manager
                $actionMessage = "updating manager for account"

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
                            Message = "Updated manager for account with AccountReference: $($outputContext.AccountReference | ConvertTo-Json). Old value: $($previousManagerId | ConvertTo-Json). New value: $($actionContext.References.ManagerAccount | ConvertTo-Json)."
                            IsError = $false
                        })
                }
                else {
                    Write-Warning "DryRun: Would update manager for account with AccountReference: $($outputContext.AccountReference | ConvertTo-Json). Old value: $($previousManagerId | ConvertTo-Json). New value: $($actionContext.References.ManagerAccount | ConvertTo-Json)."
                }
                #endregion Set Manager

                break
            }

            "NoChanges" {
                #region No changes
                $actionMessage = "skipping updating manager for account"

                #region Set ManagerId
                $outputContext.Data | Add-Member -MemberType NoteProperty -Name "managerId" -Value $actionContext.References.ManagerAccount -Force
                #endregion Set ManagerId

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        # Action  = "" # Optional
                        Message = "Skipped updating manager for account with AccountReference: $($outputContext.AccountReference | ConvertTo-Json). Reason: No changes."
                        IsError = $false
                    })
                #endregion No changes
    
                break
            }

            "Clear" {
                #region Clear manager
                # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: DELETE /api/users/{identifier}/manager
                $actionMessage = "clearing manager for account"

                $clearManagerSplatParams = @{
                    Uri         = "$($actionContext.Configuration.MWPApiBaseUrl)/users/$($outputContext.AccountReference)/manager"
                    Method      = "DELETE"
                    Verbose     = $false
                    ErrorAction = "Stop"
                }

                Write-Verbose "SplatParams: $($clearManagerSplatParams | ConvertTo-Json)"

                if (-Not($actionContext.DryRun -eq $true)) {
                    # Add header after printing splat
                    $clearManagerSplatParams['Headers'] = $headers

                    $clearManagerResponse = Invoke-RestMethod @clearManagerSplatParams

                    #region Set ManagerId
                    $outputContext.Data | Add-Member -MemberType NoteProperty -Name "managerId" -Value $actionContext.References.ManagerAccount -Force
                    #endregion Set ManagerId

                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            # Action  = "" # Optional
                            Message = "Cleared manager for account with AccountReference: $($outputContext.AccountReference | ConvertTo-Json). Old value: $($previousManagerId | ConvertTo-Json)."
                            IsError = $false
                        })
                }
                else {
                    Write-Warning "DryRun: Would clear manager for account with AccountReference: $($outputContext.AccountReference | ConvertTo-Json). Old value: $($previousManagerId | ConvertTo-Json)."
                }
                #endregion Clear manager

                break
            }
        }
    }
    #endregion Manager
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
}