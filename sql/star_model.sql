

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO
--------------dim names
CREATE TABLE [dbo].[dim_names](
	[sid] [bigint] primary key,
	[first_name]  [nvarchar](265) NULL,
	[sex]  [nvarchar](10) NULL,
) 
GO

CREATE TYPE [dbo].[DimNamesType] AS TABLE(
    [sid] [bigint],
	[first_name]  [nvarchar](265) NULL,
	[sex]  [nvarchar](10) NULL
)
GO

CREATE PROCEDURE spOverwriteDimNames
    @DimNames [dbo].[DimNamesType] READONLY
AS
BEGIN
    ;WITH DeduplicatedSource AS (
        SELECT
            sid,
            first_name,
            sex
        FROM
            @DimNames
        GROUP BY
            sid,
            first_name,
            sex
    )
    MERGE [dbo].[dim_names] AS target
    USING DeduplicatedSource AS source
    ON (target.sid = source.sid)
    WHEN MATCHED THEN
        UPDATE SET first_name = source.first_name, sex = source.sex
    WHEN NOT MATCHED THEN
        INSERT (sid, first_name, sex)
        VALUES (source.sid, source.first_name, source.sex);
END
GO

--------------dim years
CREATE TABLE [dbo].[dim_years](
	[sid] [bigint] primary key,
	[year]  [int] NULL
) 
GO

CREATE TYPE [dbo].[DimYearsType] AS TABLE(
    [sid] [bigint],
	[year]  [int] NULL
)
GO

CREATE PROCEDURE spOverwriteDimYears
    @DimYears [dbo].[DimYearsType] READONLY
AS
BEGIN
    ;WITH DeduplicatedSource AS (
        SELECT
            sid,
            year
        FROM
            @DimYears
        GROUP BY
            sid,
            year
    )
MERGE [dbo].[dim_years] AS target
USING DeduplicatedSource AS source
ON (target.sid = source.sid)
WHEN MATCHED THEN
    UPDATE SET year = source.year
WHEN NOT MATCHED THEN
    INSERT (sid, year)
    VALUES (source.sid, source.year);
END
GO
--------------dim locations
CREATE TABLE [dbo].[dim_locations](
	[sid] [bigint] primary key,
	[county]  [nvarchar](265) NULL
) 
GO

CREATE TYPE [dbo].[DimLocationsType] AS TABLE(
    [sid] [bigint],
	[county]  [nvarchar](265) NULL
)
GO

CREATE PROCEDURE spOverwriteDimLocations
    @DimLocations [dbo].[DimLocationsType] READONLY
AS
BEGIN
    ;WITH DeduplicatedSource AS (
        SELECT
            sid,
            county
        FROM
            @DimLocations
        GROUP BY
            sid,
            county
    )
MERGE [dbo].[dim_locations] AS target
USING DeduplicatedSource AS source
ON (target.sid = source.sid)
WHEN MATCHED THEN
    UPDATE SET county = source.county
WHEN NOT MATCHED THEN
    INSERT (sid, county)
    VALUES (source.sid, source.county);
END
GO
----------------------fact_babynames
CREATE TABLE [dbo].[fact_babynames](
	[sid] [bigint] primary key,
	[nameSid] [bigint] NULL,
	[yearSid] [bigint] NULL,
	[locationSid] [bigint] NULL,
	[count] [int] NULL,
) 
GO

CREATE TYPE [dbo].[FactBabyNamesType] AS TABLE(
    [sid] [bigint],
	[nameSid] [bigint] NULL,
	[yearSid] [bigint] NULL,
	[locationSid] [bigint] NULL,
	[count] [int] NULL
)
GO

-- Alter the FactBabyNames table to add the foreign key constraint
ALTER TABLE [dbo].[fact_babynames]
ADD CONSTRAINT FK_fact_babynames_dim_names FOREIGN KEY (nameSid)
REFERENCES [dbo].[dim_names] (sid);
GO
ALTER TABLE [dbo].[fact_babynames]
ADD CONSTRAINT FK_fact_babynames_dim_year FOREIGN KEY (yearSid)
REFERENCES [dbo].[dim_years] (sid);
GO
ALTER TABLE [dbo].[fact_babynames]
ADD CONSTRAINT FK_fact_babynames_dim_location FOREIGN KEY (locationSid)
REFERENCES [dbo].[dim_locations] (sid);
GO

CREATE PROCEDURE spOverwriteFactBabyNamesType
    @FactBabyNames [dbo].[FactBabyNamesType] READONLY
AS
BEGIN
    ;WITH DeduplicatedSource AS (
        SELECT
            sid,
            nameSid,
            yearSid,
            locationSid,
            count,
            ROW_NUMBER() OVER (PARTITION BY sid ORDER BY sid) AS row_num
        FROM
            @FactBabyNames
    )
    ,FilteredSource AS (
        SELECT
            sid,
            nameSid,
            yearSid,
            locationSid,
            count
        FROM
            DeduplicatedSource
        WHERE
            row_num = 1
    )
MERGE [dbo].[fact_babynames] AS target
USING FilteredSource AS source
ON (target.sid = source.sid)
WHEN MATCHED THEN
    UPDATE SET 
        nameSid = source.nameSid, 
        yearSid = source.yearSid, 
        locationSid = source.locationSid, 
        count = source.count
WHEN NOT MATCHED THEN
    INSERT (sid, nameSid, yearSid, locationSid, count)
    VALUES (source.sid, source.nameSid, source.yearSid, source.locationSid, source.count);
END
GO
