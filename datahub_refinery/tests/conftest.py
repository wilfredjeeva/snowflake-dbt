
# conftest.py
import snowflake.connector
import os, sys, logging, pytest, traceback
from dotenv import load_dotenv

print("=== DEBUG PATHS ===")
print("__file__:", __file__)
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SRC_PATH = os.path.join(PROJECT_ROOT, 'src')
print("PROJECT_ROOT:", PROJECT_ROOT)
print("SRC_PATH:", SRC_PATH)
print("Exists src?:", os.path.isdir(SRC_PATH))
print("Exists sf_client.py?:", os.path.isfile(os.path.join(SRC_PATH, "sf_client.py")))
print("sys.path head:", sys.path[:5])

if SRC_PATH not in sys.path:
    sys.path.insert(0, SRC_PATH)

print("sys.path head (after):", sys.path[:5])
print("Try import sf_client…")
try:
    import sf_client
    print("Imported sf_client OK.")
    print("Members:", [m for m in dir(sf_client) if m.lower().startswith("snowflakeclient") or m=="SnowflakeClient"])
except Exception:
    print("FAILED import sf_client. Full traceback below:")
    traceback.print_exc()
    raise

from sf_client import SnowflakeClient

load_dotenv()

# Optionally configure root logging once for tests
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger(__name__)

def pytest_addoption(parser):
    parser.addoption('--sf-account',   action='store', default=os.getenv('SNOWFLAKE_ACCOUNT'))
    # parser.addoption('--sf-host',      action='store', default=os.getenv('SNOWFLAKE_HOST'))
    parser.addoption('--sf-user',      action='store', default=os.getenv('SNOWFLAKE_USER'))
    # parser.addoption('--sf-password',  action='store', default=os.getenv('SNOWFLAKE_PASSWORD'))
    parser.addoption('--sf-role',      action='store', default=os.getenv('SNOWFLAKE_ROLE'))
    parser.addoption('--sf-warehouse', action='store', default=os.getenv('SNOWFLAKE_WAREHOUSE'))
    parser.addoption('--sf-database',  action='store', default=os.getenv('SNOWFLAKE_DATABASE'))
    parser.addoption('--sf-schema',    action='store', default=os.getenv('SNOWFLAKE_SCHEMA'))
    parser.addoption('--disable-ocsp', action='store_true', default=False)
    # JWT / key-pair auth options
    parser.addoption('--sf-authenticator', action='store',
                     default=os.getenv('SNOWFLAKE_AUTHENTICATOR', 'SNOWFLAKE_JWT'))
    parser.addoption('--sf-private-key-path', action='store',
                     default=os.getenv('SNOWFLAKE_PRIVATE_KEY_PATH'))


@pytest.fixture(scope="session")
def sf_conn(pytestconfig):
    conn = snowflake.connector.connect(
        account=pytestconfig.getoption('--sf-account'),
        # host=pytestconfig.getoption('--sf-host'),
        user=pytestconfig.getoption('--sf-user'),
        password=pytestconfig.getoption('--sf-password'),
        role=pytestconfig.getoption('--sf-role'),
        warehouse=pytestconfig.getoption('--sf-warehouse'),
        database=pytestconfig.getoption('--sf-database'),
        schema=pytestconfig.getoption('--sf-schema')
    )
    cur = conn.cursor()
    log.info('Opening Snowflake connection...')
    yield cur
    log.info('Closing Snowflake connection.')
    cur.close()

@pytest.fixture(scope='session')
def sf(pytestconfig):
    client = SnowflakeClient(
        account=pytestconfig.getoption('--sf-account'),
        # host=pytestconfig.getoption('--sf-host'),
        user=pytestconfig.getoption('--sf-user'),
        password=pytestconfig.getoption('--sf-password'),
        role=pytestconfig.getoption('--sf-role'),
        warehouse=pytestconfig.getoption('--sf-warehouse'),
        database=pytestconfig.getoption('--sf-database'),
        schema=pytestconfig.getoption('--sf-schema'),
        disable_ocsp_checks=pytestconfig.getoption('--disable-ocsp'),
    )
    log.info('Opening Snowflake connection...')
    client.connect()
    yield client
    log.info('Closing Snowflake connection.')
    client.close()
