#################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Permissions-AuthenticationMethods-Grant
# Grant authentication method to account
# PowerShell V2
#################################################

# Permission configuration
$onlySetWhenEmpty = $false

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

    #region Get current authentication methods
    # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: GET /api/users/{identifier}/authentication
    $actionMessage = "querying current authentication methods for account with AccountReference: $($actionContext.References.Account | ConvertTo-Json)"
    $getCurrentAuthenticationMethodsSplatParams = @{
        Uri         = "$($actionContext.Configuration.MWPApiBaseUrl)/users/$($actionContext.References.Account)/authentication"
        Method      = "GET"
        Headers     = $headers
        Verbose     = $false
        ErrorAction = "Stop"
    }
    $currentAuthenticationMethods = Invoke-RestMethod @getCurrentAuthenticationMethodsSplatParams
    Write-Verbose "Current authentication methods: $($currentAuthenticationMethods | ConvertTo-Json -Depth 10)"
    #endregion Get current authentication methods
    
    #region Determine value to set
    $valueToSet = $null
    $currentValue = $null

    # Flatten authentication methods array
    $methods = $currentAuthenticationMethods
    if ($methods -is [array]) {
        $methodsArray = $methods
    } elseif ($methods -is [hashtable] -or $methods -is [PSCustomObject]) {
        $methodsArray = @()
        foreach ($key in $methods.PSObject.Properties.Name) {
            $methodsArray += $methods.$key
        }
    } else {
        $methodsArray = @($methods)
    }
    switch ($actionContext.References.Permission.Method) {
        "phone" {
            # Determine which phone number to use based on type
            switch ($actionContext.References.Permission.Type) {
                "mobile" {
                    $valueToSet = $PersonContext.Person.Contact.Personal.Phone.Mobile
                    break
                }
                "alternateMobile" {
                    $valueToSet = $PersonContext.Person.Contact.Personal.Phone.Mobile
                    break
                }
                "office" {
                    $valueToSet = $PersonContext.Person.Contact.Business.Phone.Mobile
                    break
                }
            }
            # Format phone number
            if ($null -ne $valueToSet -and $valueToSet) {
                $valueToSet = $valueToSet -replace "-", "" -replace "\s", ""
                if ($valueToSet.StartsWith("06")) {
                    $valueToSet = "+316" + $valueToSet.Substring(2)
                }
                elseif ($valueToSet.StartsWith("0031")) {
                    $valueToSet = "+31" + $valueToSet.Substring(4)
                }
                elseif ($valueToSet.StartsWith("00")) {
                    $valueToSet = "+" + $valueToSet.Substring(2)
                }
                if (-not $valueToSet.StartsWith("+")) {
                    $valueToSet = "+" + $valueToSet
                }
            }
            # Get current phone authentication method value from flat array
            $currentMethod = $methodsArray | Where-Object { $_.method -eq "Phone" -and $_.phoneType -eq $actionContext.References.Permission.Type }
            if ($null -ne $currentMethod) {
                $currentValue = $currentMethod.phoneNumber -replace '\s', ''
            }
            break
        }
        "email" {
            $valueToSet = $PersonContext.Person.Contact.Business.Email
            # Get current email authentication method value from flat array
            $currentMethod = $methodsArray | Where-Object { $_.method -eq "Email" }
            if ($null -ne $currentMethod) {
                $currentValue = $currentMethod.emailAddress
            }
            break
        }
    }
    #endregion Determine value to set

    #region Calculate action
    $actionMessage = "calculating action"

    if (($currentValue | Measure-Object).count -eq 0 -or [string]::IsNullOrEmpty($currentValue)) {
        $action = 'GrantPermission'
    }
    elseif ($onlySetWhenEmpty -eq $true) {
        $action = "ExistingData-SkipUpdate"
    }
    else {
        # Verwijder spaties uit valueToSet voor correcte vergelijking (currentValue is al opgeschoond)
        $valueToSetCompare = $valueToSet -replace '\s', ''
        if ($currentValue -ne $valueToSetCompare) {
            $action = "UpdatePermission"
        } 
        else {
            $action = 'NoChanges'
        }
    }

    Write-Information "Current value: [$currentValue], Value to set: [$valueToSet], Action: [$action]"
    #endregion Calculate action

    #region Process
    switch ($action) {
        'GrantPermission' {
            $actionMessage = "creating authentication method [$($actionContext.References.Permission.Method)] - [$($actionContext.References.Permission.Type)] for account to [$valueToSet]"
            Write-Information $actionMessage

            switch ($actionContext.References.Permission.Method) {
                "phone" {
                    # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: POST /api/users/{identifier}/authentication/phone
                    $grantPermissionBody = @{
                        phoneNumber = $valueToSet
                        phoneType   = $actionContext.References.Permission.Type
                    }
                    break
                }
                "email" {
                    # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: POST /api/users/{identifier}/authentication/email
                    $grantPermissionBody = @{
                        emailAddress = $valueToSet
                    }
                    break
                }
            }

            $grantPermissionSplatParams = @{
                Uri         = "$($actionContext.Configuration.MWPApiBaseUrl)/users/$($actionContext.References.Account)/authentication/$($actionContext.References.Permission.Method)"
                Method      = "POST"
                Body        = ($grantPermissionBody | ConvertTo-Json -Depth 10)
                Headers     = $headers
                Verbose     = $false
                ErrorAction = "Stop"
            }

            $displayName = $actionContext.PermissionDisplayName
            if ([string]::IsNullOrEmpty($displayName)) {
                $displayName = "method: $($actionContext.References.Permission.Method), type: $($actionContext.References.Permission.Type)"
            }
            if (-Not($actionContext.DryRun -eq $true)) {
                Write-Information "Granting KPN-Lisa authentication method permission: [$displayName]"
                $grantPermissionResponse = Invoke-RestMethod @grantPermissionSplatParams
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Granted authentication method permission [$displayName] to account with AccountReference: $($actionContext.References.Account | ConvertTo-Json)"
                        IsError = $false
                    })
            }
            else {
                Write-Information "[DryRun] Grant authentication method permission: [$displayName], will be executed during enforcement"
            }

            $outputContext.Success = $true
            break
        }

        'UpdatePermission' {
            $actionMessage = "updating authentication method [$($actionContext.References.Permission.Method)] - [$($actionContext.References.Permission.Type)] for account to [$valueToSet]"
            Write-Information $actionMessage

            switch ($actionContext.References.Permission.Method) {
                "phone" {
                    # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: PUT /api/users/{identifier}/authentication/phone
                    $updatePermissionBody = @{
                        phoneNumber = $valueToSet
                        phoneType   = $actionContext.References.Permission.Type
                    }
                    break
                }
                "email" {
                    # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: PUT /api/users/{identifier}/authentication/email
                    $updatePermissionBody = @{
                        emailAddress = $valueToSet
                    }
                    break
                }
            }

            $updatePermissionSplatParams = @{
                Uri         = "$($actionContext.Configuration.MWPApiBaseUrl)/users/$($actionContext.References.Account)/authentication/$($actionContext.References.Permission.Method)"
                Method      = "PUT"
                Body        = ($updatePermissionBody | ConvertTo-Json -Depth 10)
                Headers     = $headers
                Verbose     = $false
                ErrorAction = "Stop"
            }

            if (-Not($actionContext.DryRun -eq $true)) {
                Write-Information "Updating KPN-Lisa authentication method permission: [$($actionContext.PermissionDisplayName)]"
                $updatePermissionResponse = Invoke-RestMethod @updatePermissionSplatParams
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Updated authentication method permission [$($actionContext.PermissionDisplayName)] for account with AccountReference: $($actionContext.References.Account | ConvertTo-Json)"
                        IsError = $false
                    })
            }
            else {
                Write-Information "[DryRun] Update authentication method permission: [$($actionContext.PermissionDisplayName)], will be executed during enforcement"
            }

            $outputContext.Success = $true
            break
        }

        "NoChanges" {
            $actionMessage = "skipping setting authentication method [$($actionContext.References.Permission.Method)] - [$($actionContext.References.Permission.Type)] for account"
            Write-Information $actionMessage
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Skipped setting authentication method [$($actionContext.PermissionDisplayName)]. Reason: No changes"
                    IsError = $false
                })
            break
        }

        "ExistingData-SkipUpdate" {
            $actionMessage = "skipping setting authentication method [$($actionContext.References.Permission.Method)] - [$($actionContext.References.Permission.Type)] for account"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Skipped setting authentication method [$($actionContext.PermissionDisplayName)]. Reason: Configured to only update when empty but already contains data"
                    IsError = $false
                })
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
        Write-Warning "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }

    $outputContext.AuditLogs.Add([PSCustomObject]@{
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
