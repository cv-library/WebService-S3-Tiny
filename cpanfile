requires 'HTTP::Tiny';

on test => sub {
    requires 'Test2::V0';
    requires 'HTTP::Request';
};
