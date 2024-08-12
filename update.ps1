###################################################################
# HelloID-Conn-Prov-Target-KPNLisa-Update
# PowerShell V2
###################################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

$nonUpdatableFields = @(
    'userPrincipalName'
    'mail'
)

#region functions
function Get-LisaAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]
        $TenantId,

        [Parameter(Mandatory)]
        [string]
        $ClientId,

        [Parameter(Mandatory)]
        [string]
        $ClientSecret,

        [Parameter(Mandatory)]
        [string]
        $Scope
    )

    try {
        $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
        $headers.Add('Content-Type', 'application/x-www-form-urlencoded')

        $body = @{
            grant_type    = 'client_credentials'
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
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Resolve-ErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )

    process {
        $exceptionObject = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = $null
            VerboseErrorMessage   = $null
        }

        switch ($ErrorObject.Exception.GetType().FullName) {
            "Microsoft.PowerShell.Commands.HttpResponseException" {
                $exceptionObject.ErrorMessage = $ErrorObject.ErrorDetails.Message
                break
            }
            "System.Net.WebException" {
                $exceptionObject.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                break
            }
            default {
                $exceptionObject.ErrorMessage = $ErrorObject.Exception.Message
            }
        }

        $exceptionObject.VerboseErrorMessage = @(
            "Error at Line [$($ErrorObject.InvocationInfo.ScriptLineNumber)]: $($ErrorObject.InvocationInfo.Line)."
            "ErrorMessage: $($exceptionObject.ErrorMessage) [$($ErrorObject.ErrorDetails.Message)]"
        ) -Join " "

        Write-Output $exceptionObject
    }
}
#endregion functions

try {
    # Retrieve token
    $splatGetTokenParams = @{
        TenantId     = $config.TenantId
        ClientId     = $config.ClientId
        ClientSecret = $config.ClientSecret
        Scope        = $config.Scope
    }
    $accessToken = (Get-LisaAccessToken @splatGetTokenParams).access_token
    $authorizationHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $authorizationHeaders.Add("Authorization", "Bearer $accessToken")
    $authorizationHeaders.Add("Content-Type", "application/json")
    $authorizationHeaders.Add("Mwp-Api-Version", "1.0")

    # Get correlated account
    $splatGetAccountParams = @{
        Uri     = "$($actionContext.Configuration.BaseUrl)/Users/$($actionContext.References.Account)"
        Method  = 'GET'
        Headers = $authorizationHeaders
    }
    $correlatedAccount = Invoke-RestMethod @splatGetAccountParams
    $outputContext.PreviousData = $correlatedAccount | Select-Object -Property ([array] $outputContext.Data.PSObject.Properties.Name)

    # Update account
    if (-Not ($actionContext.DryRun -eq $true)) {
        Write-Information "Updating KPN Lisa account for '$($personContext.Person.DisplayName)'"
        $splatUpdateAccountParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/Users/$($actionContext.References.Account)/bulk"
            Method  = "Patch"
            Body    = $outputContext.Data | Select-Object -Property * -ExcludeProperty $nonUpdatableFields
            Headers = $authorizationHeaders
        }
        $null = Invoke-RestMethod @splatUpdateAccountParams

        $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = "Account for '$($personContext.Person.DisplayName)' Updated. ObjectId: '$($actionContext.References.Account)'"
            IsError = $false
        })

    }

    # Update manager
    if ($null -eq $actionContext.References.ManagerAccount) {
        if (-Not ($actionContext.DryRun -eq $true)) {
            $splatUpdateManagerParams = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/Users/$($actionContext.References.Account)/manager"
                Method  = 'DELETE'
                Headers = $authorizationHeaders
            }
            $null = Invoke-RestMethod @splatUpdateManagerParams
        }

        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = "Manager for '$($personContext.Person.DisplayName)' deleted. ObjectId: '$($UserResponse.objectId)'"
                IsError = $false
            })
    } else {
        if (-Not ($actionContext.DryRun -eq $true)) {
            $splatUpdateAccountParams = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/Users/$($actionContext.References.Account)/Manager"
                Method  = "Put"
                Body    = $actionContext.References.ManagerAccount
                Headers = $authorizationHeaders
            }
            $null = Invoke-RestMethod @splatUpdateAccountParams
        }

        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = "Manager for '$($personContext.Person.DisplayName)' Updated. ObjectId: '$($UserResponse.objectId)'"
                IsError = $false
            })
    }

    $outputContext.Success = $true
} catch {
    $errorObj = Resolve-ErrorMessage -ErrorObject $_
    Write-Warning $errorObj.VerboseErrorMessage
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = "Error updating account [$($personContext.Person.DisplayName) ($($actionContext.References.Account))]. Error Message: $($errorObj.ErrorMessage)."
            IsError = $true
        })
}
