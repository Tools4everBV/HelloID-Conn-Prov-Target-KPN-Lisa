###################################################################
# HelloID-Conn-Prov-Target-KPNLisa-Create
# PowerShell V2
###################################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Get-LisaAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]
        $TenantId,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]
        $ClientId,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]
        $ClientSecret,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]
        $Scope,

        [Parameter()]
        [switch]
        $AsSecureString
    )

    try {
        $SplatParams = @{
            Uri         = "https://login.microsoftonline.com/$($TenantId)/oauth2/v2.0/token/"
            ContentType = "application/x-www-form-urlencoded"
            Method      = "Post"
            Body        = @{
                grant_type    = "client_credentials"
                client_id     = $ClientId
                client_secret = $ClientSecret
                scope         = $Scope
            }
        }
        $Response = Invoke-RestMethod @SplatParams

        if ($AsSecureString) {
            Write-Output ($Response.access_token | ConvertTo-SecureString -AsPlainText)
        }
        else {
            Write-Output ($Response.access_token)
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}


function Resolve-ErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]
        $ErrorObject
    )

    process {
        $Exception = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = $Null
            VerboseErrorMessage   = $Null
        }

        switch ($ErrorObject.Exception.GetType().FullName) {
            "Microsoft.PowerShell.Commands.HttpResponseException" {
                $Exception.ErrorMessage = $ErrorObject.ErrorDetails.Message
                break
            }
            "System.Net.WebException" {
                $Exception.ErrorMessage = [System.IO.StreamReader]::new(
                    $ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                break
            }
            default {
                $Exception.ErrorMessage = $ErrorObject.Exception.Message
            }
        }

        $Exception.VerboseErrorMessage = @(
            "Error at Line [$($ErrorObject.InvocationInfo.ScriptLineNumber)]: $($ErrorObject.InvocationInfo.Line)."
            "ErrorMessage: $($Exception.ErrorMessage) [$($ErrorObject.ErrorDetails.Message)]"
        ) -Join " "

        Write-Output $Exception
    }
}
#endregion functions


# Start Script
try {
    # Formatting Headers and authentication for KPN Lisa Requests
    $LisaRequest = @{
        Authentication = "Bearer"
        Token          = $actionContext.Configuration.AzureAD | Get-LisaAccessToken -AsSecureString
        ContentType    = "application/json; charset=utf-8"
        Headers        = @{
            "Mwp-Api-Version" = "1.0"
        }
    }

    #region Correlation
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $CorrelationField = $actionContext.CorrelationConfiguration.accountField
        $CorrelationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ($Null -eq $CorrelationField -or $Null -eq $CorrelationValue) {
            throw "Correlation is enabled but not configured correctly."
        }

        #  Write logic here that checks if the account can be correlated in the target system
        $SplatParams = @{
            Uri    = "$($actionContext.Configuration.BaseUrl)/Users"
            Method = "Get"
            Body   = @{
                filter = "$($CorrelationField) eq '$($CorrelationValue)'"
            }
        }
        $CorrelatedAccount = Invoke-RestMethod @LisaRequest @SplatParams

        if ($CorrelatedAccount.count -gt 1) {
            throw "Multiple accounts found with filter: $($SplatParams.Body.filter)"
        }

        if ($CorrelatedAccount.count -eq 1) {
            $CorrelatedAccount = $CorrelatedAccount.value

            $outputContext.AccountReference = $CorrelatedAccount.id

            $outputContext.Data.PSObject.Properties | ForEach-Object {
                if ($CorrelatedAccount.PSobject.Properties.Name.Contains($PSItem.Name)) {
                    $outputContext.Data.$($PSItem.Name) = $CorrelatedAccount.$($PSItem.Name)
                }
            }

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = "CorrelateAccount" # Optionally specify a different action for this audit log
                    Message = "Correlated account with username $($CorrelatedAccount.UserName) on field $($CorrelationField) with value $($CorrelationValue)"
                    IsError = $False
                })

            $outputContext.Success = $True
            $outputContext.AccountCorrelated = $True
        }
    }
    #endregion correlation

    # Create KPN Lisa Account
    if (-Not $outputContext.AccountCorrelated) {

        $CreationProperties = @(
            "changePasswordNextSignIn", "usageLocation", "preferredLanguage",
            "givenName", "surName", "displayName", "userPrincipalName"
        )

        Write-Verbose -Verbose "Creating KPN Lisa account for '$($personContext.Person.DisplayName)'"

        if ($outputContext.Data.PSobject.Properties.Name.Contains("mail") -and $Null -eq $outputContext.Data.mail) {
            $outputContext.Data.mail = $outputContext.Data.userPrincipalName
        }

        $Body = $outputContext.Data | Select-Object $CreationProperties

        $SplatParams = @{
            Uri    = "$($actionContext.Configuration.BaseUrl)/Users"
            Method = "Post"
            Body   = $Body
        }

        if (-Not ($actionContext.DryRun -eq $True)) {
            $UserResponse = Invoke-RestMethod @LisaRequest @SplatParams
            $outputContext.AccountReference = $UserResponse.objectId
        }
        else {
            Write-Verbose -Verbose ($Body | ConvertTo-Json)
            $outputContext.AccountReference = 'unknown'
        }


        $outputContext.Data | Add-Member -NotePropertyMembers @{
            password = $UserResponse.temporaryPassword
        } -Force

        #Update the user with all other props
        $Body = $outputContext.Data | Select-Object -Property *, "accountEnabled" -ExcludeProperty @(
            $CreationProperties, "password"
        )

        # Force the account disabled
        $Body.accountEnabled = $False

        $SplatParams = @{
            Uri    = "$($actionContext.Configuration.BaseUrl)/Users/$($outputContext.AccountReference)/bulk"
            Method = "Patch"
            Body   = $Body
        }

        if (-Not ($actionContext.DryRun -eq $True)) {
            [void] (Invoke-RestMethod @LisaRequest @SplatParams)
        }
        else {
            Write-Verbose -Verbose ($Body | ConvertTo-Json)
        }

        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = "CreateAccount" # Optionally specify a different action for this audit log
                Message = "Created account for '$($personContext.Person.DisplayName)'. Id: $($outputContext.AccountReference)"
                IsError = $False
            })

        # Set the manager
        if ($actionContext.References.ManagerAccount) {
            $SplatParams = @{
                Uri    = "$($actionContext.Configuration.BaseUrl)/Users/$($outputContext.AccountReference)/Manager"
                Method = "Put"
                Body   = $actionContext.References.ManagerAccount
            }

            if (-Not ($actionContext.DryRun -eq $True)) {
                [void] (Invoke-RestMethod @LisaRequest @SplatParams)
            }

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = "CreateAccount" # Optionally specify a different action for this audit log
                    Message = "Added Manager $($personContext.Manager.displayName) to '$($personContext.Person.DisplayName)'"
                    IsError = $False
                })
        }

        $outputContext.Success = $True
    }
}
catch {
    $Exception = $PSItem | Resolve-ErrorMessage

    Write-Verbose -Verbose $Exception.VerboseErrorMessage

    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = "CreateAccount" # Optionally specify a different action for this audit log
            Message = "Error creating account [$($personContext.Person.DisplayName)]. Error Message: $($Exception.ErrorMessage)."
            IsError = $True
        })
}
