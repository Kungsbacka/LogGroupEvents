# LogGroupEvents

Inserts group related events into a database table for auditing.

## Usage
* Rename Config.example.ps1 to Config.ps1 and change the content to match your environment.
* Create database objects below.
* Run the script as a user with permission to read the domain controller security log. One solution is to create a new security group and give that group read permission to the registry key HKLM\System\CurrentControlSet\Services\Eventlog\Security on all domain controllers.

## Database table
```sql
CREATE TABLE [dbo].[GroupEvent](
	[id] [binary](32) NOT NULL,
	[timeCreated] [datetime] NOT NULL,
	[domainController] [varchar](50) NOT NULL,
	[eventId] [int] NOT NULL,
	[groupName] [varchar](256) NOT NULL,
	[groupSid] [varchar](184) NOT NULL,
	[memberName] [varchar](256) NOT NULL,
	[memberSid] [varchar](184) NOT NULL,
	[userName] [varchar](256) NOT NULL,
	[userSid] [varchar](184) NOT NULL,
    CONSTRAINT [PK_GroupEvent] PRIMARY KEY NONCLUSTERED ([id] ASC)
)
```

## Stored procedure
```sql
CREATE PROCEDURE [dbo].[spInsertNewGroupEvent]
	@idString varchar(1024),
	@timeCreated datetime,
	@domainController varchar(50),
	@eventId int,
	@groupName varchar(256),
	@groupSid varchar(184),
	@memberName varchar(256),
	@memberSid varchar(184),
	@userName varchar(256),
	@userSid varchar(184)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @id binary(32);
	SET @id = HASHBYTES('SHA2_256', @idString);
	IF NOT EXISTS
	(
		SELECT 1 FROM dbo.GroupEvent WHERE id = @id
	)
	BEGIN
		BEGIN TRY
			BEGIN TRANSACTION;
			INSERT INTO dbo.GroupEvent (id, timeCreated, domainController, eventId, groupName, groupSid, memberName, memberSid, userName, userSid)
				VALUES (@id, @timeCreated, @domainController, @eventId, @groupName, @groupSid, @memberName, @memberSid, @userName, @userSid);
			COMMIT TRANSACTION;
		END TRY
		BEGIN CATCH
			ROLLBACK TRANSACTION;
		END CATCH
	END
END
```
