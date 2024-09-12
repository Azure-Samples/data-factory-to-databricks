create user [dataFactoryUserIdentity] from external provider
GO;

alter role db_datareader add member [dataFactoryUserIdentity]
GO;

alter role db_datawriter add member [dataFactoryUserIdentity]
GO;

GRANT EXECUTE TO [dataFactoryUserIdentity]
GO;

-- Grant permissions on the ghb schema
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::data TO [dataFactoryUserIdentity];
GO;