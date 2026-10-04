import json,os,stat,sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import weather_location as loc
class WeatherLocation(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        env=patch.dict(os.environ,{'XDG_CACHE_HOME':self.tmp.name});env.start();self.addCleanup(env.stop)
        self.response={'success':True,'city':'Example Town','region':'Example Region','country':'Example Country','latitude':12.3456,'longitude':-23.4567,'ip':'private-value-not-to-store','connection':{'isp':'private-network'}}
    def test_lookup_caches_only_required_fields(self):
        with patch.object(loc,'request',return_value=self.response) as fetch:
            first=loc.locate(now=100000);second=loc.locate(now=100001)
        self.assertEqual(fetch.call_count,1);self.assertTrue(second['cached']);self.assertEqual(first['latitude'],12.35)
        cached=loc.cache_path().read_text();self.assertNotIn('private-',cached);self.assertNotIn('connection',cached)
        self.assertEqual(stat.S_IMODE(loc.cache_path().stat().st_mode),0o600)
    def test_expired_cache_refreshes(self):
        with patch.object(loc,'request',return_value=self.response) as fetch:
            loc.locate(now=100000);loc.locate(now=200000)
        self.assertEqual(fetch.call_count,2)
    def test_offline_uses_last_known_location(self):
        with patch.object(loc,'request',return_value=self.response):loc.locate(now=100000)
        with patch.object(loc,'request',side_effect=OSError('offline')) as fetch:
            self.assertTrue(loc.locate(now=200000)['stale']);loc.locate(now=200001)
        self.assertEqual(fetch.call_count,1)
    def test_failed_lookup_backs_off_across_restarts(self):
        with patch.object(loc,'request',side_effect=OSError('offline')) as fetch:
            for moment in [100000,100001]:
                with self.assertRaises(RuntimeError):loc.locate(now=moment)
        self.assertEqual(fetch.call_count,1)
    def test_forced_lookup_is_rate_limited(self):
        with patch.object(loc,'request',return_value=self.response) as fetch:
            loc.locate(now=100000);loc.locate(force=True,now=100001);loc.locate(force=True,now=100061)
        self.assertEqual(fetch.call_count,2)
    def test_invalid_or_failed_response_is_not_stored(self):
        for data in [dict(self.response,latitude=float('nan')),dict(self.response,longitude=200),{'success':False}]:
            loc.cache_path().unlink(missing_ok=True)
            with patch.object(loc,'request',return_value=data):
                with self.assertRaises(RuntimeError):loc.locate(now=100000)
            self.assertNotIn('location',json.loads(loc.cache_path().read_text()))
    def test_city_results_have_region_and_country(self):
        row={'name':'Example City','admin1':'Example Region','country':'Example Country','latitude':0,'longitude':0}
        with patch.object(loc,'request',return_value={'results':[row,dict(row,latitude=999)]}) as fetch:
            result=loc.search('Example City, Example Region')
        self.assertEqual(len(result['results']),1);self.assertEqual(result['results'][0]['latitude'],0)
        self.assertIn('name=Example+City%2C+Example+Region',fetch.call_args.args[0])
    def test_short_search_does_not_query_provider(self):
        with patch.object(loc,'request') as fetch:
            with self.assertRaises(ValueError):loc.search('x')
        fetch.assert_not_called()
