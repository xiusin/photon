module config

// config/mail.v — 邮件配置
//
// 定义邮件驱动、SMTP 主机端口、发件人等配置。

// MailConfigBlock 邮件配置块
pub struct MailConfigBlock {
pub:
	driver    string
	host      string
	port      int
	username  string
	password  string
	from      string
	from_name string
}

// default_mail_config 返回指定 profile 的邮件默认配置
pub fn default_mail_config(profile string) MailConfigBlock {
	mut driver := env_or('MAIL_DRIVER', 'log')

	match profile {
		'prod' {
			driver = env_or('MAIL_DRIVER', 'smtp')
		}
		else {
			driver = env_or('MAIL_DRIVER', 'log')
		}
	}

	return MailConfigBlock{
		driver: driver
		host: env_or('MAIL_HOST', 'localhost')
		port: env_or_int('MAIL_PORT', 587)
		username: env_or('MAIL_USERNAME', '')
		password: env_or('MAIL_PASSWORD', '')
		from: env_or('MAIL_FROM', 'noreply@photonblog.dev')
		from_name: env_or('MAIL_FROM_NAME', 'PhotonBlog')
	}
}
