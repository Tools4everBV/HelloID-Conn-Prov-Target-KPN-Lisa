#################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Permissions-AuthenticationMethods-Revoke
# Revoke authentication method from account
# PowerShell V2
#################################################

# Permission configuration
$removeWhenRevokingEntitlement = $false

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

    #region Determine current value and method ID (flat array)
    $currentValue = $null
    $authenticationMethodId = $null

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
            $currentMethod = $methodsArray | Where-Object { $_.method -eq "Phone" -and $_.phoneType -eq $actionContext.References.Permission.Type }
            if ($null -ne $currentMethod) {
                $currentValue = $currentMethod.phoneNumber
                $authenticationMethodId = $currentMethod.id
            }
            break
        }
        "email" {
            $currentMethod = $methodsArray | Where-Object { $_.method -eq "Email" }
            if ($null -ne $currentMethod) {
                $currentValue = $currentMethod.emailAddress
                $authenticationMethodId = $currentMethod.id
            }
            break
        }
    }
    #endregion Determine current value and method ID

    #region Calculate action
    $actionMessage = "calculating action"

    if (($currentValue | Measure-Object).count -eq 0 -or [string]::IsNullOrEmpty($currentValue)) {
        $action = 'NoExistingData-SkipDelete'
    }
    elseif ($removeWhenRevokingEntitlement -eq $false) {
        $action = 'SkipDelete'
    }
    else {
        $action = 'RevokePermission'
    }

    Write-Information "Current value: [$currentValue], Action: [$action]"
    #endregion Calculate action

    #region Process
    switch ($action) {
        'RevokePermission' {
            # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: DELETE /api/users/{identifier}/authentication/{authenticationmethod}/{authenticationmethodId}
            $actionMessage = "deleting authentication method [$($actionContext.References.Permission.Method)] - [$($actionContext.References.Permission.Type)] for account"
            Write-Information $actionMessage

            $revokePermissionSplatParams = @{
                Uri         = "$($actionContext.Configuration.MWPApiBaseUrl)/users/$($actionContext.References.Account)/authentication/$($actionContext.References.Permission.Method)/$authenticationMethodId"
                Method      = "DELETE"
                Headers     = $headers
                Verbose     = $false
                ErrorAction = "Stop"
            }

            $displayName = $actionContext.PermissionDisplayName
            if ([string]::IsNullOrEmpty($displayName)) {
                $displayName = "method: $($actionContext.References.Permission.Method), type: $($actionContext.References.Permission.Type)"
            }
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Revoking KPN-Lisa authentication method permission: [$displayName]"
                $revokePermissionResponse = Invoke-RestMethod @revokePermissionSplatParams

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Revoked authentication method permission [$displayName] from account with AccountReference: $($actionContext.References.Account | ConvertTo-Json)"
                        IsError = $false
                    })
            }
            else {
                Write-Information "[DryRun] Revoke authentication method permission: [$displayName], will be executed during enforcement"
            }

            $outputContext.Success = $true
            break
        }

        'SkipDelete' {
            $actionMessage = "skipping deleting authentication method [$($actionContext.References.Permission.Method)] - [$($actionContext.References.Permission.Type)] for account"
            Write-Information $actionMessage
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Skipped deleting authentication method [$($actionContext.PermissionDisplayName)]. Reason: Configured to not delete on revoke of entitlement"
                    IsError = $false
                })
            break
        }

        'NoExistingData-SkipDelete' {
            $actionMessage = "skipping deleting authentication method [$($actionContext.References.Permission.Method)] - [$($actionContext.References.Permission.Type)] for account"
            Write-Information $actionMessage
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Skipped deleting authentication method [$($actionContext.PermissionDisplayName)]. Reason: Nothing to delete"
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
