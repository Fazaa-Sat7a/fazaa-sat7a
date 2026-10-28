import com.fazaa.admin.UpdatePolicy;
public class UpdatePolicyChecks {
 static void ok(boolean b){if(!b)throw new AssertionError();}
 public static void main(String[] args){String p=UpdatePolicy.PACKAGE,u="https://github.com/Fazaa-Sat7a/fazaa-sat7a/releases/download/admin-v1012/fazaa-admin.apk";
 ok(UpdatePolicy.accepts(p,1011,p,1012,u));ok(!UpdatePolicy.accepts(p,1012,p,1012,u));ok(!UpdatePolicy.accepts(p,1013,p,1012,u));
 ok(!UpdatePolicy.accepts(p,1011,"com.fazaa.customer.test",1012,u));ok(!UpdatePolicy.accepts(p+".dev",11,p,1012,u));
 for(String bad:new String[]{u.replace("https:","http:"),u.replace("github.com","example.com"),u.replace("github.com","github.com@evil.test"),u+"?redirect=evil",u.replace("admin-v1012","admin-v1013"),u.replace("fazaa-admin.apk","customer.apk")})ok(!UpdatePolicy.accepts(p,1011,p,1012,bad));
 System.out.println("PASS version comparison, correct package, owned immutable HTTPS download and malformed targets");}
}
