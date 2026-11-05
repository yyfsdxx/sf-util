/**
 * Juj_JigyoCsvUploaderController のテストクラス
 */
@IsTest
private class Juj_JigyoCsvUploaderControllerTest {

    @IsTest
    static void getLoginUserInfo_returnsUserTypeAndSibuCode() {
        Test.startTest();
        Map<String, Object> result = Juj_JigyoCsvUploaderController.getLoginUserInfo();
        Test.stopTest();

        Assert.areEqual(Juj_JigyoCsvUploaderController.TEMP_USER_TYPE, result.get('userType'), 'ユーザ種別');
        Assert.areEqual(Juj_JigyoCsvUploaderController.TEMP_SIBU_CODE, result.get('sibuCode'), '支部コード');
    }
}
