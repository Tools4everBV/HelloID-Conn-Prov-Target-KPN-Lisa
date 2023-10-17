#####################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Create
#
# Version: 1.0.0.0
#####################################################

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
        $RestMethod = @{
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
        $Response = Invoke-RestMethod @RestMethod

        Write-Output $Response.access_token
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}


function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]
        $ErrorObject
    )

    process {
        $httpError = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }

        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpError.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpError.ErrorMessage = [System.IO.StreamReader]::new(
                $ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }

        Write-Output $httpError
    }
}


function Get-ErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]
        $ErrorObject
    )

    process {
        $ErrorMessage = [PSCustomObject]@{
            VerboseErrorMessage = $Null
            AuditErrorMessage   = $Null
        }

        if (
            $ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException' -or
            $ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException'
        ) {
            $HttpErrorObject = $ErrorObject | Resolve-HTTPError

            $ErrorMessage.VerboseErrorMessage = $HttpErrorObject.ErrorMessage
            $ErrorMessage.AuditErrorMessage = $HttpErrorObject.ErrorMessage
        }

        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($ErrorMessage.VerboseErrorMessage)) {
            $ErrorMessage.VerboseErrorMessage = $ErrorObject.Exception.Message
        }
        if ([String]::IsNullOrEmpty($ErrorMessage.AuditErrorMessage)) {
            $ErrorMessage.AuditErrorMessage = $ErrorObject.Exception.Message
        }

        Write-Output $ErrorMessage
    }
}
#endregion functions

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = @(
    [Net.SecurityProtocolType]::Tls
    [Net.SecurityProtocolType]::Tls11
    [Net.SecurityProtocolType]::Tls12
)

#region Aliasses
$Config = $ActionContext.Configuration
$Account = $OutputContext.Data
$AuditLogs = $OutputContext.AuditLogs

$Person = $PersonContext.Person
$Manager = $PersonContext.Manager
#endregion Aliasses

# Start Script
try {
    # TODO:: stukje beunen voor required fields, met harde error als hier niet aan voldaan wordt

    Write-Verbose -Verbose "Getting accessToken"

    $SplatParams = @{
        TenantId     = $Config.TenantId
        ClientId     = $Config.ClientId
        ClientSecret = $Config.ClientSecret
        Scope        = $Config.Scope
    }
    $accessToken = Get-LisaAccessToken @SplatParams

    $AuthorizationHeaders = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $AuthorizationHeaders.Add("Authorization", "Bearer $($accessToken)")
    $AuthorizationHeaders.Add("Content-Type", "application/json")
    $AuthorizationHeaders.Add("Mwp-Api-Version", "1.0")

    #region Correlation
    if ($ActionContext.CorrelationConfiguration.Enabled) {
        $CorrelationField = $ActionContext.CorrelationConfiguration.accountField
        $CorrelationValue = $ActionContext.CorrelationConfiguration.PersonFieldValue

        if ($Null -eq $CorrelationField -or $Null -eq $CorrelationValue) {
            Write-Warning "Correlation is enabled but not configured correctly."
        }

        #  Write logic here that checks if the account can be correlated in the target system
        $SplatParams = @{
            Uri     = "$($Config.BaseUrl)/Users"
            Headers = $AuthorizationHeaders
            Method  = 'Get'
            Body    = @{
                filter = "$($CorrelationField)+eq+'$($CorrelationValue)'"
            }
        }
        $CorrelatedAccount = Invoke-RestMethod @SplatParams

        if ($CorrelatedAccount.count -gt 1) {
            throw "Multiple accounts found with filter: $($SplatParams.Body.filter)"
        }

        if ($CorrelatedAccount.count -eq 1) {
            $CorrelatedAccount = $CorrelatedAccount.value

            $OutputContext.AccountReference = $CorrelatedAccount.id

            $Account.PSObject.Properties | ForEach-Object {
                if ($CorrelatedAccount.PSobject.Properties.Name.Contains($_.Name)) {
                    $Account.$($_.Name) = $CorrelatedAccount.$($_.Name)
                }
            }

            $AuditLogs.Add([PSCustomObject]@{
                    Action  = "CorrelateAccount" # Optionally specify a different action for this audit log
                    Message = "Correlated account with username $($CorrelatedAccount.UserName) on field $($CorrelationField) with value $($CorrelationValue)"
                    IsError = $False
                })

            $OutputContext.Success = $True
            $OutputContext.AccountCorrelated = $True
        }
    }
    #endregion correlation

    # Create KPN Lisa Account
    if (-Not $OutputContext.AccountCorrelated) {

        Write-Verbose -Verbose "Creating KPN Lisa account for '$($Person.DisplayName)'"

        if ($Account.PSobject.Properties.Name.Contains("mail") -and $Null -eq $Account.mail) {
            $Account.mail = $Account.userPrincipalName
        }

        $Body = $Account | Select-Object @(
            'changePasswordNextSignIn', 'usageLocation', 'preferredLanguage',
            'givenName', 'surName', 'displayName', 'userPrincipalName'
        )

        $SplatParams = @{
            Uri     = "$($Config.BaseUrl)/Users"
            Headers = $AuthorizationHeaders
            Method  = 'Post'
            Body    = $Body | ConvertTo-Json
        }

        if (-Not ($ActionContext.DryRun -eq $True)) {
            $userResponse = Invoke-RestMethod @SplatParams

            $OutputContext.AccountReference = $userResponse.objectId
            $Account | Add-Member -NotePropertyName 'password' -NotePropertyValue $userResponse.temporaryPassword
        }
        else {
            Write-Verbose -Verbose (
                $SplatParams.Body
            )

            $Account | Add-Member -NotePropertyName 'password' -NotePropertyValue "FakePassword"
        }

        #Update the user with all other props
        $Body = $Account | Select-Object -Property *, 'accountEnabled' -ExcludeProperty @(
            'changePasswordNextSignIn', 'usageLocation', 'preferredLanguage',
            'givenName', 'surName', 'displayName', 'userPrincipalName',
            'password'
        )

        # Force the account disabled
        $Body.accountEnabled = $False

        $SplatParams = @{
            Uri     = "$($config.BaseUrl)/Users/$($OutputContext.AccountReference)/bulk"
            Headers = $AuthorizationHeaders
            Method  = 'Patch'
            Body    = $Body | ConvertTo-Json
        }

        if (-Not ($ActionContext.DryRun -eq $True)) {
            [void] (Invoke-RestMethod @SplatParams)
        }
        else {
            Write-Verbose -Verbose (
                $SplatParams.Body
            )
        }

        # Set the manager
        if ($PersonContext.References.ManagerAccount) {
            $SplatParams = @{
                Uri     = "$($Config.BaseUrl)/Users/$($OutputContext.AccountReference)/Manager"
                Headers = $AuthorizationHeaders
                Method  = 'Put'
                Body    = $PersonContext.References.ManagerAccount
            }

            if (-Not ($ActionContext.DryRun -eq $True)) {
                [void] (Invoke-RestMethod @SplatParams)
            }

            Write-Verbose -Verbose "Added Manager $($Manager.displayName) to '$($Person.DisplayName)'"
        }

        $AuditLogs.Add([PSCustomObject]@{
                Action  = "CreateAccount" # Optionally specify a different action for this audit log
                Message = "Created account for '$($Person.DisplayName)'. Id: $($OutputContext.AccountReference)"
                IsError = $False
            })

        $OutputContext.Success = $True
    }
}
catch {
    $ex = $PSItem
    $ErrorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose -Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ErrorMessage.VerboseErrorMessage) [$($ex.ErrorDetails.Message)]"

    $AuditLogs.Add([PSCustomObject]@{
            Action  = "CreateAccount" # Optionally specify a different action for this audit log
            Message = "Error creating account [$($Person.DisplayName)]. Error Message: $($ErrorMessage.AuditErrorMessage)."
            IsError = $True
        })
}
