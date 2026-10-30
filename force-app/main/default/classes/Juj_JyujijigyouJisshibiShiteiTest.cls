/**
 * Juj_JyujijigyouJisshibiShiteiController のテストクラス
 */
@IsTest
private class Juj_JyujijigyouJisshibiShiteiTest {

    private static final String JIGYO_NO = '0000001';
    private static final String BASYO_NO = '0000000001';
    private static final String NENDO = '2026';
    private static final String WRONG_JIGYO_NO = '9999999';
    private static final String MEMBER_NO = '1234567';
    private static final String SODANIN_NO = '7654321';

    @TestSetup
    static void setup() {
        Account shibu = new Account(Name = 'テスト事務局', Jims_Sibu_Code__c = '001', Jims_Sibu_Name__c = 'テスト支部');
        insert shibu;
        Juji_Basyo_Master__c basyo = new Juji_Basyo_Master__c(
            JujM_Juji_Basyo_No__c = BASYO_NO,
            JujM_Juji_Basyo_Name__c = 'テスト場所',
            // 従事事業の入力規則：従事事業の事務所・法人と同じ支部コード
            JujM_Sibu_Code__c = '001'
        );
        insert basyo;
        Juji_Jigyo__c jigyo = new Juji_Jigyo__c(
            Juji_Juji_Jigyo_No__c = JIGYO_NO,
            Juji_Juji_Basyo_Master__c = basyo.Id,
            Juji_Jisi_Nendo__c = NENDO,
            Juji_Juji_Jigyo_Name__c = 'テスト事業',
            // 従事事業の入力規則を満たす値
            Juji_Syakin_Siharai_Hoho__c = '謝金無',
            Juji_Kotuhi_Siharai_Hoho__c = '交通費無',
            Juji_Internet_Bosyu_Kubun__c = '募集する',
            Juji_Internet_Bosyu_Kikan_From__c = Date.today().addDays(-30),
            Juji_Internet_Bosyu_Kikan_To__c = Date.today().addDays(60),
            Juji_Internet_Bosyu_Taisyo__c = '限定無し',
            Juji_Jimusyo_Hojin__c = shibu.Id
        );
        insert jigyo;
        // 実施日：11/3（時間帯2件。逆順に登録し、使用しない項目も含める）、11/10（時間帯1件）、12/1
        insert new List<Juji_Jigyo_Meisai__c>{
            new Juji_Jigyo_Meisai__c(
                Juji_Meisai_Juji_Jigyo__c = jigyo.Id,
                Juji_Meisai_Jisi_Nengapi__c = Date.newInstance(2026, 11, 3),
                Juji_Meisai_Bosyu_Ninzu__c = 5,
                Juji_Meisai_Kaisi_Jikoku__c = Time.newInstance(9, 0, 0, 0),
                Juji_Meisai_Syuryo_Jikoku__c = Time.newInstance(15, 0, 0, 0),
                Juji_Meisai_Biko__c = '午前・午後',
                Juji_Meisai_JisshiJikantai_Meisai__c = '[{"startTime":"13:00","endTime":"15:00","count":2,"shiharaiKingaku":"1000"},'
                    + '{"startTime":"09:00","endTime":"12:00","count":3}]'
            ),
            new Juji_Jigyo_Meisai__c(
                Juji_Meisai_Juji_Jigyo__c = jigyo.Id,
                Juji_Meisai_Jisi_Nengapi__c = Date.newInstance(2026, 11, 10),
                Juji_Meisai_Bosyu_Ninzu__c = 1,
                Juji_Meisai_JisshiJikantai_Meisai__c = '[{"startTime":"10:00","endTime":"11:00","count":1}]'
            ),
            new Juji_Jigyo_Meisai__c(
                Juji_Meisai_Juji_Jigyo__c = jigyo.Id,
                Juji_Meisai_Jisi_Nengapi__c = Date.newInstance(2026, 12, 1),
                Juji_Meisai_Bosyu_Ninzu__c = 2,
                Juji_Meisai_JisshiJikantai_Meisai__c = '[{"startTime":"10:00","endTime":"11:00","count":2}]'
            )
        };
        Contact member = new Contact(Kaii_Toroku_No__c = MEMBER_NO, LastName = 'テスト 太郎');
        insert member;
        Soudanin_Master__c sodanin = new Soudanin_Master__c(SouM_Sodanin_No__c = SODANIN_NO, SouM_Sodanin_Name__c = '相談 花子');
        insert sodanin;

        // 割当：会員は 11/10 に仮割当（本人割当済）、相談員は 11/3 の 09:00-12:00・13:00-15:00 に確定
        insert new List<Juji_Jigyo_Wariate__c>{
            new Juji_Jigyo_Wariate__c(
                Wari_Juji_Jigyo__c = jigyo.Id,
                Wari_Kaiin__c = member.Id,
                Wari_Juji_Nengapi__c = Date.newInstance(2026, 11, 10),
                Wari_Wriate_Flag__c = Juj_JyujijigyouJisshibiShiteiController.FLAG_ON,
                Wari_JisshiJikantai_Meisai__c = '[{"startTime":"10:00","endTime":"11:00"}]'
            ),
            new Juji_Jigyo_Wariate__c(
                Wari_Juji_Jigyo__c = jigyo.Id,
                Wari_Soudanin_Master__c = sodanin.Id,
                Wari_Juji_Nengapi__c = Date.newInstance(2026, 11, 3),
                Wari_Kakutei_Flag__c = Juj_JyujijigyouJisshibiShiteiController.FLAG_ON,
                Wari_JisshiJikantai_Meisai__c = '[{"startTime":"09:00","endTime":"12:00","unused":"x"},{"startTime":"13:00","endTime":"15:00"}]'
            )
        };
    }

    // ==================== ヘルパー ====================
    private static Object get(Map<String, Object> m, String path) {
        Object current = m;
        for (String key : path.split('\\.')) {
            if (current == null) {
                return null;
            }
            current = ((Map<String, Object>) current).get(key);
        }
        return current;
    }

    private static void assertAuraError(List<String> expected, Exception e) {
        Assert.isInstanceOfType(e, AuraHandledException.class);
        Assert.areEqual(expected[1], e.getMessage());
    }

    // ==================== init ====================
    // 会員
    @IsTest
    static void init_member() {
        Map<String, Object> r = Juj_JyujijigyouJisshibiShiteiController.init(JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO);
        Assert.areEqual('テスト事業', get(r, 'jigyo.jigyoName'));
        Assert.areEqual('001', get(r, 'jigyo.shibuCode'));
        Assert.areEqual('テスト支部', get(r, 'jigyo.shibuName'), '支部名は Jims_Sibu_Name__c（Name ではない）');
        Assert.areEqual('テスト場所', get(r, 'jigyo.basyoName'));
        Assert.areEqual('テスト 太郎', get(r, 'jujishaName'));
        Assert.areEqual('2026-11-03', get(r, 'minJisshibi'));
        Assert.areEqual('2026-12-01', get(r, 'maxJisshibi'));
        // 本人割当済（仮割当を含む）
        List<Object> own = (List<Object>) get(r, 'ownAssigned');
        Assert.areEqual(1, own.size());
        Map<String, Object> k = (Map<String, Object>) own[0];
        Assert.areEqual('2026-11-10', k.get('kanoubiDate'));
        Map<String, Object> slot = (Map<String, Object>) ((List<Object>) k.get('timeSlots'))[0];
        Assert.areEqual('10:00', slot.get('startTime'));
        Assert.areEqual('11:00', slot.get('endTime'));
    }

    // 相談員
    @IsTest
    static void init_sodanin() {
        Map<String, Object> r = Juj_JyujijigyouJisshibiShiteiController.init(JIGYO_NO, BASYO_NO, NENDO, SODANIN_NO);
        Assert.areEqual('相談 花子', get(r, 'jujishaName'));
        Assert.areEqual('2026-11-03', get((Map<String, Object>) ((List<Object>) get(r, 'ownAssigned'))[0], 'kanoubiDate'));
    }

    // 実施日なしは範囲null
    @IsTest
    static void init_noJisshibi_rangeNull() {
        delete [SELECT Id FROM Juji_Jigyo_Meisai__c];
        Map<String, Object> r = Juj_JyujijigyouJisshibiShiteiController.init(JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO);
        Assert.isNull(get(r, 'minJisshibi'));
        Assert.isNull(get(r, 'maxJisshibi'));
    }

    // 事業なしはエラー
    @IsTest
    static void init_jigyoNotFound_error() {
        try {
            Juj_JyujijigyouJisshibiShiteiController.init(WRONG_JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO);
            Assert.fail('例外が発生すること');
        } catch (Exception e) {
            assertAuraError(Juj_JyujijigyouJisshibiShiteiController.E_JIGYO_NOT_FOUND, e);
        }
    }

    // 従事者なしはエラー
    @IsTest
    static void init_jujishaNotFound_error() {
        try {
            Juj_JyujijigyouJisshibiShiteiController.init(JIGYO_NO, BASYO_NO, NENDO, '9999999');
            Assert.fail('例外が発生すること');
        } catch (Exception e) {
            assertAuraError(Juj_JyujijigyouJisshibiShiteiController.E_JUJISHA_NOT_FOUND, e);
        }
    }

    // 番号未入力はエラー
    @IsTest
    static void init_blankNo_error() {
        try {
            Juj_JyujijigyouJisshibiShiteiController.init(JIGYO_NO, BASYO_NO, NENDO, '');
            Assert.fail('例外が発生すること');
        } catch (Exception e) {
            assertAuraError(Juj_JyujijigyouJisshibiShiteiController.E_JUJISHA_NOT_FOUND, e);
        }
    }

    // ==================== getDays ====================
    // 表示期間内の実施日と時間帯
    @IsTest
    static void getDays_daysAndSlotsInPeriod() {
        List<Map<String, Object>> days = Juj_JyujijigyouJisshibiShiteiController.getDays(JIGYO_NO, BASYO_NO, NENDO, '2026-11-01', '2026-11-30');
        Assert.areEqual(2, days.size(), '12/1 は表示期間外');

        Map<String, Object> day = days[0];
        Assert.areEqual('2026-11-03', day.get('jisshibi'));
        Assert.areEqual(5, day.get('boshuNinzu'));
        Assert.areEqual('09:00', day.get('startTime'), '開始時間（時間型）は HH:mm で返すこと');
        Assert.areEqual('15:00', day.get('endTime'));
        Assert.areEqual('午前・午後', day.get('biko'));
        Assert.areEqual(2, day.get('wariateNinzu'), '日付行は各時間帯の割当人数の合計（1人で2時間帯＝2）');

        List<Object> slots = (List<Object>) day.get('timeSlots');
        Assert.areEqual(2, slots.size());
        Map<String, Object> first = (Map<String, Object>) slots[0];
        Assert.areEqual('09:00', first.get('startTime'), '開始時間の昇順');
        Assert.areEqual('12:00', first.get('endTime'));
        Assert.areEqual(3, first.get('count'));
        Assert.areEqual(1, first.get('wariateNinzu'), 'その時間帯を含む確定割当の件数');
        Map<String, Object> second = (Map<String, Object>) slots[1];
        Assert.areEqual('13:00', second.get('startTime'));
        Assert.areEqual(1, second.get('wariateNinzu'));
        Assert.areEqual(0, days[1].get('wariateNinzu'), '仮割当は割当人数に含めない');
    }

    // 事業なしはエラー
    @IsTest
    static void getDays_jigyoNotFound_error() {
        try {
            Juj_JyujijigyouJisshibiShiteiController.getDays(WRONG_JIGYO_NO, BASYO_NO, NENDO, '2026-11-01', '2026-11-30');
            Assert.fail('例外が発生すること');
        } catch (Exception e) {
            assertAuraError(Juj_JyujijigyouJisshibiShiteiController.E_JIGYO_NOT_FOUND, e);
        }
    }

    // ==================== checkSave ====================
    // 正常
    @IsTest
    static void checkSave_ok() {
        Juj_JyujijigyouJisshibiShiteiController.checkSave(JIGYO_NO, BASYO_NO, NENDO);
        Assert.isTrue(true, '例外が発生しないこと');
    }

    // 事業なしはエラー
    @IsTest
    static void checkSave_jigyoNotFound_error() {
        try {
            Juj_JyujijigyouJisshibiShiteiController.checkSave(WRONG_JIGYO_NO, BASYO_NO, NENDO);
            Assert.fail('例外が発生すること');
        } catch (Exception e) {
            assertAuraError(Juj_JyujijigyouJisshibiShiteiController.E_JIGYO_NOT_FOUND, e);
        }
    }

    // ==================== 変換 ====================
    // 未設定・形式不正は空
    @IsTest
    static void parseSlots_blankOrInvalid_empty() {
        Assert.areEqual(0, Juj_JyujijigyouJisshibiShiteiController.parseSlots(null).size());
        Assert.areEqual(0, Juj_JyujijigyouJisshibiShiteiController.parseSlots('not json').size());
    }

    // 時間型とテキスト
    @IsTest
    static void toTimeText_timeAndText() {
        Assert.isNull(Juj_JyujijigyouJisshibiShiteiController.toTimeText(null));
        Assert.areEqual('09:30', Juj_JyujijigyouJisshibiShiteiController.toTimeText(Time.newInstance(9, 30, 0, 0)));
        Assert.areEqual('13:00', Juj_JyujijigyouJisshibiShiteiController.toTimeText('13:00'));
    }

    // 開始と終了
    @IsTest
    static void slotKey_startAndEnd() {
        Assert.areEqual('09:00-12:00', Juj_JyujijigyouJisshibiShiteiController.slotKey('09:00', '12:00'));
    }
}
